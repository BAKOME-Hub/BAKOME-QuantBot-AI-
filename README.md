# BAKOME QuantBot AI

**BAKOME QuantBot AI** – Robot de trading quantitatif pour MetaTrader 5 (MT5) intégrant un modèle neuronal ONNX, une API de sentiment d'actualités, un filtre de corrélation multi-symboles et une gestion avancée des risques. Compatible avec tous les brokers MT5 (indices, métaux, forex).

---

## 🚀 Fonctionnalités

- 🧠 **Modèle ONNX** : inférence rapide d'un réseau de neurones (remplacez par votre propre modèle `.onnx`).
- 📰 **API News** : récupération du sentiment de marché via API REST (Bloomberg, ForexFactory, personnalisable).
- 🔗 **Corrélation multi-symboles** : filtre les signaux basé sur la corrélation avec d'autres instruments (US30, NASDAQ, SP500, etc.).
- 📊 **Gestion des risques avancée** :
  - Drawdown maximal journalier (2% par défaut)
  - Taille de position dynamique basée sur l'ATR
  - Limite d'ordres par heure (évite le sur-trading)
  - Spread maximal autorisé
- ⚡ **Exécution rapide** : ordres placés directement via MT5, sans latence.
- 🔓 **100% open source** – aucune dépendance externe, code transparent.

---

## 📦 Installation

1. **Copier** le fichier `BAKOME_QuantBot_AI.mq5` dans le dossier `MQL5/Experts/` de votre plateforme MT5.
2. **Compiler** (F7) dans MetaEditor.
3. **Attacher** le bot à un graphique (XAUUSD, US30, NASDAQ, etc.).
4. **Paramétrer** les entrées selon votre tolérance au risque.

---

## 🧠 Modèle ONNX

Par défaut, le bot utilise un modèle interne (fallback). Pour utiliser votre propre réseau de neurones :

1. Entraînez un modèle et exportez-le au format `.onnx` (par exemple avec PyTorch ou TensorFlow).
2. Placez le fichier dans `MQL5/Files/`.
3. Définissez le paramètre `InpONNXModelFile` avec le nom du fichier.
4. Activez `InpUseONNX = true`.

**Structure d'entrée du modèle** (8 features) :
- 0 : Momentum (prix relatif sur 50 périodes)
- 1 : Spread normalisé
- 2 : Volume normalisé
- 3 : ATR / prix (volatilité)
- 4 : Sentiment des news (valeur entre -1 et +1)
- 5 : Heure de trading (sinus)
- 6 : Variation du prix sur 1 minute
- 7 : RSI simplifié

**Sortie du modèle** : probabilité entre 0 et 1 (0 = SELL fort, 1 = BUY fort).

---

## 📰 API News (optionnelle)

Pour activer le sentiment d'actualités en temps réel :

1. Définissez `InpNewsAPIUrl` avec l'URL de votre endpoint (ex: `https://api.example.com/news/sentiment`).
2. Activez `InpUseNewsFilter = true`.
3. Assurez-vous que votre URL retourne un JSON contenant un champ `"sentiment": 0.35` (entre -1 et +1).

> **Note** : Par défaut, le bot utilise une simulation aléatoire. Remplacez la fonction `GetNewsSentiment()` par un véritable appel `WebRequest()` (nécessite d'activer les requêtes web dans MT5 : Outils → Options → Experts Advisors → "Allow WebRequest").

---

## 🔗 Corrélation multi-symboles

Le bot peut filtrer les signaux en fonction de la corrélation avec d'autres instruments (ex: US30, NASDAQ, DAX). Pour l'activer :

- Définissez `InpUseCorrelation = true`
- Renseignez `InpCorrelationSymbols` avec la liste des symboles séparés par des virgules (ex: `US30,NASDAQ,SP500`).

Le signal est pondéré par la corrélation moyenne : si les symboles corrélés vont dans la direction opposée, le signal est atténué.

---

## ⚙️ Paramètres d'entrée

| Paramètre | Description | Valeur par défaut |
|-----------|-------------|-------------------|
| `InpLotSize` | Taille de base (lots) | 0.1 |
| `InpMaxDrawdownPct` | Drawdown max journalier (%) | 2.0 |
| `InpRiskPerTrade` | Risque par trade (% du capital) | 1.0 |
| `InpSignalThreshold` | Seuil de confiance (0.5 à 0.9) | 0.6 |
| `InpMomentumPeriod` | Période pour le momentum | 50 |
| `InpATRPeriod` | Période ATR (volatilité) | 14 |
| `InpMaxSpreadPoints` | Spread max autorisé (points) | 30 |
| `InpMaxOrdersPerHour` | Ordres max par heure | 3 |
| `InpUseONNX` | Utiliser un modèle ONNX | true |
| `InpONNXModelFile` | Nom du fichier `.onnx` | bakome_model.onnx |
| `InpNewsAPIUrl` | URL de l'API news | (vide) |
| `InpUseCorrelation` | Activer le filtre de corrélation | true |
| `InpCorrelationSymbols` | Symboles pour corrélation | US30,NASDAQ,SP500 |

---

## ⚠️ Avertissement

Ce logiciel est fourni **à titre éducatif uniquement**.  
Testez toujours d'abord sur un **compte de démonstration** avant toute utilisation en réel.  
Les performances passées ne préjugent pas des résultats futurs.  
Le trading comporte un risque de perte en capital. L'auteur n'est pas responsable des pertes éventuelles.

---

## 💛 Soutien

Ce projet a été développé par **Bakome**, un jeune développeur autodidacte de Goma (RDC).  
Tout le code a été écrit sur un simple téléphone, sans ordinateur.

Si ce travail vous est utile, un petit don (même symbolique) aide à continuer.

**Adresses crypto :**
- **BTC** : `bc1qhtjp3qpqru4vuqd355dfcn46mqjrlpdfmngk6u0`
- **ETH** : `0x2fD73626714d9e37EA464109F8eCeA2CA5401062`
- **SOL** : `3CfhghA7hSNPBbd1RME5rRDm5UUeesTq9NKTcyzZdkz4`
- **USDT (TRC20)** : `THkLdiKsmscJFwBPA4tpWeAn1xVw7DTKxq`

Merci du fond du cœur. 🙏

---

## 📜 Licence

MIT – voir fichier [LICENSE](LICENSE).

---

**Built on a phone. Powered by passion.** 🚀
