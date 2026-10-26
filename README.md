# Agent de contexte (bêta)

Agent de contexte est une app pour Mac qui t'aide à garder une trace de ton travail. Elle repère tes tâches à partir des apps que tu utilises, du texte de la fenêtre active et de tes actions dans Chrome. Quand un choix n'est pas évident, elle te pose une question courte. Le soir, elle prépare des fiches que tu relis.

Tout reste sur ton Mac. Le texte est analysé par OpenAI avec ta clé. Il n'est pas utilisé pour entraîner un modèle.

## Installer

Il faut un Mac avec macOS 14 (Sonoma) ou plus récent, Apple ou Intel. Ouvre le Terminal et colle cette ligne :

```sh
curl -fsSL https://raw.githubusercontent.com/sashabriffaux-png/context-agent-releases/main/install.sh | bash
```

Le script télécharge la dernière version, vérifie que le téléchargement est intact (somme SHA-256 : elle prouve que le fichier n'a pas été abîmé en route, pas qui l'a publié), l'installe dans Applications (ou dans `~/Applications` si tu n'as pas les droits d'administrateur), puis l'ouvre.

## Ce que l'app te demande

Au premier lancement, une visite guidée te montre les réglages :

1. **Les autorisations macOS** : enregistrement de l'écran (pour lire le texte de la fenêtre active, aucune image n'est gardée) et accessibilité (pour savoir quelle app est au premier plan).
2. **Ta clé** : celle que tu as reçue. Elle est gardée dans le Trousseau de ton Mac.
3. **L'extension Chrome** : un guide pas à pas te montre comment la charger dans `chrome://extensions`. Le lien entre Chrome et l'app s'installe tout seul.
4. **Ta carte d'équipe** : la carte « VC » est déjà choisie. Tu peux en prendre une autre.

L'app vit dans la barre de menu, en haut à droite de l'écran.

## Mettre à jour

Relance la même commande. L'app est remplacée, tes réglages et tes données sont gardés.

Après une mise à jour, macOS peut te redemander les autorisations (enregistrement de l'écran, accessibilité). Si l'agent est coché dans Réglages Système mais que l'app dit encore « Refusé » : retire-le de la liste avec « – », puis ajoute-le de nouveau avec « + ».

Si ton app était dans Applications et que tu n'as pas les droits d'administrateur, la nouvelle version va dans `~/Applications` : supprime alors l'ancienne copie pour ne pas les confondre.

## Désinstaller

```sh
curl -fsSL https://raw.githubusercontent.com/sashabriffaux-png/context-agent-releases/main/uninstall.sh | bash
```

Le script supprime l'app et le lien avec Chrome. Il te demande ensuite si tu veux aussi supprimer tes données et ta base de connaissances. Pour tout supprimer sans question :

```sh
curl -fsSL https://raw.githubusercontent.com/sashabriffaux-png/context-agent-releases/main/uninstall.sh | bash -s -- --yes
```

Il reste une étape à faire toi-même : dans Chrome, ouvre `chrome://extensions` et supprime l'extension Agent de contexte.

## Ce qui reste sur ton Mac

- `~/Library/Application Support/context-agent` : tes réglages, ton historique et une copie de l'extension Chrome (gardés si tu réponds non à la désinstallation).
- `~/agent-knowledge` (ou le dossier choisi dans les réglages) : ta base de connaissances, en fichiers texte.
- Dans le Trousseau, un élément « context-agent Safe Storage » qui sert à chiffrer ta clé. Tu peux le supprimer avec l'app Trousseaux d'accès.
