//+------------------------------------------------------------------+
//|                                        BAKOME_QuantBot_AI.mq5     |
//|                                    Copyright 2026, BAKOME (DRC)   |
//|                                   https://github.com/BAKOME-Hub   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, BAKOME (Kitoko Bakome Fabrice Bandia)"
#property link      "https://github.com/BAKOME-Hub"
#property version   "1.00"
#property description "BAKOME QuantBot AI – Modèle neuronal (ONNX) + API News + Corrélations"
#property description "Architecture : features → ONNX inference → risque → ordre"
#property description "Compatible MT5 (build 3000+) avec support ONNX"

//+------------------------------------------------------------------+
//| PARAMÈTRES EXTERNES                                              |
//+------------------------------------------------------------------+
input double   InpLotSize           = 0.1;     // Taille de base (lots)
input double   InpMaxDrawdownPct    = 2.0;     // Drawdown max journalier (%)
input double   InpRiskPerTrade      = 1.0;     // Risque par trade (% du capital)
input double   InpSignalThreshold   = 0.6;     // Seuil de confiance (0.5..0.9)
input int      InpMomentumPeriod    = 50;      // Période momentum
input int      InpATRPeriod         = 14;      // Période ATR
input int      InpMaxSpreadPoints   = 30;      // Spread max autorisé (points)
input int      InpMaxOrdersPerHour  = 3;       // Ordres max par heure
input bool     InpUseONNX           = true;    // Utiliser modèle ONNX (sinon modèle simple)
input string   InpONNXModelFile     = "bakome_model.onnx"; // Fichier ONNX (dossier /Files/)
input string   InpNewsAPIUrl        = "https://api.example.com/news/sentiment"; // API news (vide = désactivé)
input bool     InpUseCorrelation    = true;    // Filtrer par corrélation multi-symboles
input string   InpCorrelationSymbols= "US30,NASDAQ,SP500"; // Symboles corrélés (séparés par des virgules)

#include <Trade/Trade.mqh>
#include <Arrays/ArrayDouble.mqh>
#include <Math/Stat/Math.mqh>
#include <ONNXRuntime/ONNXRuntime.mqh>

//+------------------------------------------------------------------+
//| GLOBALES                                                         |
//+------------------------------------------------------------------+
CTrade         trade;
MqlTick        currentTick;
MqlRates       rates[];
double         currentBalance, dailyStartBalance, dailyPnL;
datetime       lastTradeTime;
datetime       orderTimestamps[];
int            orderCountLastHour;
CArrayDouble   momentumBuffer, atrBuffer;
double         signalThreshold, riskPerTrade, maxDrawdownPct;
double         lotSizeBase;
int            maxSpreadPoints, maxOrdersPerHour;
bool           useONNX;
string         onnxModelFile;
string         newsAPIUrl;
bool           useCorrelation;
string         correlationSymbols[];
double         correlationWeights[];

// Modèle ONNX
COpenVINO        openvino;
COpenVINO_Model *model = NULL;
bool             modelLoaded = false;

//+------------------------------------------------------------------+
//| INITIALISATION                                                   |
//+------------------------------------------------------------------+
int OnInit() {
   // Paramètres
   signalThreshold   = InpSignalThreshold;
   riskPerTrade      = InpRiskPerTrade;
   maxDrawdownPct    = InpMaxDrawdownPct;
   lotSizeBase       = InpLotSize;
   maxSpreadPoints   = InpMaxSpreadPoints;
   maxOrdersPerHour  = InpMaxOrdersPerHour;
   useONNX           = InpUseONNX;
   onnxModelFile     = InpONNXModelFile;
   newsAPIUrl        = InpNewsAPIUrl;
   useCorrelation    = InpUseCorrelation;
   
   // Buffers
   momentumBuffer.Resize(InpMomentumPeriod);
   atrBuffer.Resize(InpATRPeriod);
   ArrayResize(orderTimestamps, maxOrdersPerHour);
   orderCountLastHour = 0;
   
   // Trade settings
   trade.SetExpertMagicNumber(20260519);
   trade.SetDeviationInPoints(10);
   
   // Chargement du modèle ONNX
   if(useONNX) {
      modelLoaded = LoadONNXModel();
      if(!modelLoaded) Print("⚠️ Modèle ONNX non chargé – fallback sur modèle interne");
   }
   
   // Initialisation des symboles pour corrélation
   if(useCorrelation) {
      ParseCorrelationSymbols();
      ArrayResize(correlationWeights, ArraySize(correlationSymbols));
      for(int i=0; i<ArraySize(correlationSymbols); i++) correlationWeights[i] = 1.0 / ArraySize(correlationSymbols);
   }
   
   dailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   currentBalance    = dailyStartBalance;
   dailyPnL          = 0.0;
   lastTradeTime     = 0;
   
   Print("🚀 BAKOME QuantBot AI démarré sur ", _Symbol);
   Print("📊 Capital initial: ", currentBalance);
   Print("🧠 Modèle ONNX: ", (modelLoaded ? "Chargé" : "Désactivé"));
   Print("📰 API News: ", (newsAPIUrl != "" ? "Activée" : "Désactivée"));
   Print("🔗 Corrélation: ", (useCorrelation ? "Activée (" + string(ArraySize(correlationSymbols)) + " symboles)" : "Désactivée"));
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| CHARGEMENT DU MODÈLE ONNX                                        |
//+------------------------------------------------------------------+
bool LoadONNXModel() {
   string path = "\\Files\\" + onnxModelFile;
   if(!FileIsExist(onnxModelFile, FILE_COMMON)) {
      Print("❌ Fichier ONNX introuvable: ", onnxModelFile, " (placez-le dans /MQL5/Files/)");
      return false;
   }
   model = openvino.Model(path);
   if(model == NULL) {
      Print("❌ Échec chargement modèle ONNX");
      return false;
   }
   Print("✅ Modèle ONNX chargé avec succès");
   return true;
}

//+------------------------------------------------------------------+
//| PARSING DES SYMBOLES POUR CORRÉLATION                            |
//+------------------------------------------------------------------+
void ParseCorrelationSymbols() {
   string symbols = InpCorrelationSymbols;
   string parts[];
   int count = StringSplit(symbols, ',', parts);
   if(count > 0) {
      ArrayResize(correlationSymbols, count);
      for(int i=0; i<count; i++) {
         correlationSymbols[i] = parts[i];
         Print("🔗 Symbole corrélé: ", correlationSymbols[i]);
      }
   }
}

//+------------------------------------------------------------------+
//| DEINIT                                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
   if(model != NULL) {
      delete model;
      model = NULL;
   }
   Print("🔴 BAKOME QuantBot AI arrêté");
}

//+------------------------------------------------------------------+
//| BOUCLE PRINCIPALE                                                |
//+------------------------------------------------------------------+
void OnTick() {
   if(!UpdateData()) return;
   ResetDaily();
   if(!PreTradeChecks()) return;
   
   double features[];
   ComputeFeatures(features);
   
   double prediction;
   if(useONNX && modelLoaded) {
      prediction = PredictONNX(features);
   } else {
      prediction = PredictInternal(features);
   }
   
   // Application du filtre de corrélation
   if(useCorrelation && ArraySize(correlationSymbols) > 0) {
      double corrFactor = GetCorrelationFactor();
      prediction = prediction * (0.5 + 0.5 * corrFactor);
      prediction = MathMax(0.05, MathMin(0.95, prediction));
   }
   
   string signal = GetSignal(prediction);
   if(signal != "HOLD")
      ExecuteSignal(signal, prediction);
   
   Sleep(50);
}

//+------------------------------------------------------------------+
//| MISE À JOUR DES DONNÉES                                          |
//+------------------------------------------------------------------+
bool UpdateData() {
   if(!SymbolInfoTick(_Symbol, currentTick)) return false;
   if(CopyRates(_Symbol, _Period, 0, 2, rates) < 2) return false;
   return true;
}

//+------------------------------------------------------------------+
//| RESET DRAWDOWN JOURNALIER                                        |
//+------------------------------------------------------------------+
void ResetDaily() {
   MqlDateTime today;
   TimeToCurrentTime(today);
   static int lastDay = today.day;
   if(today.day != lastDay) {
      dailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      dailyPnL          = 0.0;
      orderCountLastHour = 0;
      lastDay = today.day;
   }
   currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   dailyPnL       = currentBalance - dailyStartBalance;
}

//+------------------------------------------------------------------+
//| VÉRIFICATIONS PRÉ-TRADE                                          |
//+------------------------------------------------------------------+
bool PreTradeChecks() {
   double spread = (currentTick.ask - currentTick.bid) / _Point;
   if(spread > maxSpreadPoints) return false;
   
   datetime now = TimeCurrent();
   int validOrders = 0;
   for(int i=0; i<orderCountLastHour; i++) {
      if(now - orderTimestamps[i] <= 3600) validOrders++;
   }
   if(validOrders >= maxOrdersPerHour) return false;
   
   double drawdownPct = (dailyPnL / dailyStartBalance) * 100.0;
   if(drawdownPct <= -maxDrawdownPct) return false;
   
   return true;
}

//+------------------------------------------------------------------+
//| CALCUL DES FEATURES (entrée du modèle)                           |
//+------------------------------------------------------------------+
void ComputeFeatures(double &features[]) {
   ArrayResize(features, 8);
   
   // Feature 0 : Momentum (prix relatif)
   double price = currentTick.ask;
   momentumBuffer.Add(price);
   if(momentumBuffer.Total() > InpMomentumPeriod) momentumBuffer.Delete(0);
   if(momentumBuffer.Total() == InpMomentumPeriod) {
      double first = momentumBuffer.At(0);
      features[0] = (price - first) / first;
   } else features[0] = 0.0;
   
   // Feature 1 : Spread normalisé
   features[1] = (currentTick.ask - currentTick.bid) / _Point;
   
   // Feature 2 : Volume normalisé
   features[2] = currentTick.volume / 1000.0;
   
   // Feature 3 : ATR (volatilité)
   double atr = iATR(_Symbol, _Period, InpATRPeriod, 1);
   features[3] = atr / currentTick.ask;
   
   // Feature 4 : Sentiment des news (via API)
   features[4] = GetNewsSentiment();
   
   // Feature 5 : Heure de trading (sinus)
   MqlDateTime dt;
   TimeToCurrentTime(dt);
   features[5] = MathSin(dt.hour * 15 * M_PI / 180.0);
   
   // Feature 6 : Variation du prix sur 1 minute
   static double oldPrice = 0;
   if(oldPrice == 0) oldPrice = price;
   features[6] = (price - oldPrice) / oldPrice;
   oldPrice = price;
   
   // Feature 7 : Force relative (RSI simplifié)
   features[7] = ComputeRSI();
}

//+------------------------------------------------------------------+
//| RSI SIMPLIFIÉ                                                    |
//+------------------------------------------------------------------+
double ComputeRSI() {
   static double gains=0.0, losses=0.0;
   static double lastClose=0.0;
   double close = rates[1].close;
   if(lastClose != 0.0) {
      double change = close - lastClose;
      if(change > 0) gains += change; else losses -= change;
   }
   lastClose = close;
   if(gains+losses == 0) return 50.0;
   double rs = gains / losses;
   return 100.0 - (100.0 / (1.0 + rs));
}

//+------------------------------------------------------------------+
//| SENTIMENT DES NEWS (appel API REST)                              |
//+------------------------------------------------------------------+
double GetNewsSentiment() {
   if(newsAPIUrl == "") return 0.0;
   // Utilisation de WebRequest (nécessite activation dans MT5)
   // À adapter selon l'API réelle
   static double lastSentiment = 0.0;
   static datetime lastCall = 0;
   datetime now = TimeCurrent();
   if(now - lastCall < 300) return lastSentiment; // une fois toutes les 5 minutes
   lastCall = now;
   
   // Exemple avec WebRequest (à décommenter et adapter)
   /*
   char postData[];
   string headers = "Content-Type: application/json";
   string result;
   int timeout = 5000;
   int res = WebRequest("GET", newsAPIUrl, headers, timeout, postData, result);
   if(res == 200) {
      // Parser JSON simplifié (à adapter)
      int start = StringFind(result, "\"sentiment\":");
      if(start != -1) {
         double sent = StringToDouble(StringSubstr(result, start+12, 5));
         lastSentiment = MathMax(-1.0, MathMin(1.0, sent));
      }
   }
   */
   // Simulation temporaire (à remplacer par vrai appel)
   lastSentiment = (MathRand() / 32767.0) * 2.0 - 1.0;
   return lastSentiment;
}

//+------------------------------------------------------------------+
//| FACTEUR DE CORRÉLATION MULTI-SYMBOLES                            |
//+------------------------------------------------------------------+
double GetCorrelationFactor() {
   double totalCorr = 0.0;
   double totalWeight = 0.0;
   for(int i=0; i<ArraySize(correlationSymbols); i++) {
      string sym = correlationSymbols[i];
      double corr = CorrelationWithSymbol(sym);
      totalCorr += corr * correlationWeights[i];
      totalWeight += correlationWeights[i];
   }
   if(totalWeight > 0) totalCorr /= totalWeight;
   return MathMax(-0.5, MathMin(0.5, totalCorr));
}

//+------------------------------------------------------------------+
//| CORRÉLATION ENTRE DEUX SYMBOLES (sur 100 périodes)               |
//+------------------------------------------------------------------+
double CorrelationWithSymbol(string symbol) {
   double close1[], close2[];
   ArraySetAsSeries(close1, true);
   ArraySetAsSeries(close2, true);
   if(CopyClose(_Symbol, _Period, 0, 100, close1) < 100) return 0.0;
   if(CopyClose(symbol, _Period, 0, 100, close2) < 100) return 0.0;
   double mean1 = 0.0, mean2 = 0.0;
   for(int i=0; i<100; i++) { mean1 += close1[i]; mean2 += close2[i]; }
   mean1 /= 100; mean2 /= 100;
   double num=0.0, den1=0.0, den2=0.0;
   for(int i=0; i<100; i++) {
      double d1 = close1[i] - mean1;
      double d2 = close2[i] - mean2;
      num += d1 * d2;
      den1 += d1 * d1;
      den2 += d2 * d2;
   }
   if(den1==0 || den2==0) return 0.0;
   return num / sqrt(den1 * den2);
}

//+------------------------------------------------------------------+
//| PRÉDICTION PAR MODÈLE ONNX                                       |
//+------------------------------------------------------------------+
double PredictONNX(double &features[]) {
   if(model == NULL) return 0.5;
   // Préparation des tenseurs d'entrée
   double inputData[8];
   for(int i=0; i<8; i++) inputData[i] = features[i];
   // Inférence
   double outputData[1];
   if(!model.Run(inputData, outputData)) {
      Print("❌ Erreur inférence ONNX");
      return 0.5;
   }
   double prediction = outputData[0];
   return MathMax(0.05, MathMin(0.95, prediction));
}

//+------------------------------------------------------------------+
//| PRÉDICTION INTERNE (fallback)                                    |
//+------------------------------------------------------------------+
double PredictInternal(double &features[]) {
   double weights[8] = {0.30, 0.05, 0.05, 0.15, 0.15, 0.05, 0.10, 0.15};
   double sum = 0.0, wSum = 0.0;
   for(int i=0; i<8; i++) {
      sum += features[i] * weights[i];
      wSum += weights[i];
   }
   double raw = sum / wSum;
   double prediction = 1.0 / (1.0 + MathExp(-3.0 * raw));
   static double lastPred = 0.5;
   double smoothed = 0.7 * prediction + 0.3 * lastPred;
   lastPred = smoothed;
   return MathMax(0.05, MathMin(0.95, smoothed));
}

//+------------------------------------------------------------------+
//| GÉNÉRATION DU SIGNAL                                             |
//+------------------------------------------------------------------+
string GetSignal(double prediction) {
   if(prediction > signalThreshold)        return "BUY";
   if(prediction < 1.0 - signalThreshold) return "SELL";
   return "HOLD";
}

//+------------------------------------------------------------------+
//| EXÉCUTION DE L'ORDRE                                             |
//+------------------------------------------------------------------+
void ExecuteSignal(string signal, double prediction) {
   if(PositionSelect(_Symbol)) return;
   
   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double riskAmount = freeMargin * (riskPerTrade / 100.0);
   double lotSize = lotSizeBase;
   
   // Position sizing basé sur l'ATR
   double atr = iATR(_Symbol, _Period, InpATRPeriod, 1);
   double slPoints = atr / _Point;
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double riskPerLot = slPoints * tickValue;
   if(riskPerLot > 0) {
      lotSize = riskAmount / riskPerLot;
      lotSize = NormalizeDouble(lotSize, 2);
      lotSize = MathMax(lotSize, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN));
      lotSize = MathMin(lotSize, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX));
   }
   
   bool success = false;
   if(signal == "BUY") {
      success = trade.Buy(lotSize, _Symbol, 0, 0, 0, "BAKOME QuantBot AI BUY");
   } else if(signal == "SELL") {
      success = trade.Sell(lotSize, _Symbol, 0, 0, 0, "BAKOME QuantBot AI SELL");
   }
   
   if(success && trade.ResultRetcode() == TRADE_RETCODE_DONE) {
      Print("✅ ORDRE EXÉCUTÉ: ", signal, " | Lots: ", lotSize, " | Confiance: ", prediction);
      if(orderCountLastHour < maxOrdersPerHour) {
         orderTimestamps[orderCountLastHour] = TimeCurrent();
         orderCountLastHour++;
      }
      lastTradeTime = TimeCurrent();
   } else {
      Print("❌ Échec ordre: ", trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| FONCTION ATR                                                     |
//+------------------------------------------------------------------+
double iATR(string symbol, ENUM_TIMEFRAMES tf, int period, int shift) {
   double atr[1];
   int handle = iATR(symbol, tf, period);
   if(handle == INVALID_HANDLE) return 0.0;
   if(CopyBuffer(handle, 0, shift, 1, atr) <= 0) {
      IndicatorRelease(handle);
      return 0.0;
   }
   IndicatorRelease(handle);
   return atr[0];
}
//+------------------------------------------------------------------+
