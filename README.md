# Open Whisper

Clavier AZERTY français et dictée locale pour iPhone, à partir d’iOS 17. L’application SwiftUI capture la voix au premier plan. L’extension UIKit saisit via UITextDocumentProxy. Le moteur et ses poids résident exclusivement du côté de l’application.

## Dicter puis insérer

1. Ouvrir Open Whisper, télécharger Small ou Base et autoriser le microphone. Les poids sont vérifiés avec SHA-256 puis chargés par whisper.cpp. Un téléchargement interrompu peut être recommencé.
2. Dans Réglages → Général → Clavier → Claviers → Ajouter un clavier, choisir Open Whisper. Autoriser l’accès complet pour partager les préférences et récupérer une dictée. Le clavier alphabétique, ses suggestions et ses autres dispositions fonctionnent indépendamment.
3. Dans Open Whisper, maintenir le microphone, parler et relâcher. Glisser vers la gauche annule. Une interruption, le verrouillage ou la mise en arrière-plan interrompt la capture. La limite est de deux minutes. Le fichier PCM temporaire est supprimé après lecture, annulation et au démarrage suivant.
4. Relire puis choisir **Envoyer au clavier**. Revenir soi-même au champ de destination, choisir Open Whisper avec le globe et toucher le micro dans le bandeau. Le clavier réclame le dernier résultat une seule fois, au moment du toucher. Une nouvelle publication remplace la précédente. Après dix minutes la lecture rejette le texte. Une interruption entre la prise du résultat et son insertion peut le perdre. L’application permet de le renvoyer.
5. **Copier** permet aussi de coller avec iOS. La copie est locale à l’appareil avec expiration après dix minutes. Pour vérifier le fonctionnement hors ligne, activer le mode Avion après installation du modèle.

## Architecture et limites iOS

La disposition est dessinée avec UIKit. UITextChecker fournit les complétions et corrections françaises, complétées par quelques suites de mots locales. Le bandeau présente jusqu’à deux résultats disponibles. Les ressources de QuickType sont privées. Les accents utilisent un menu d’appui long. Les emojis sont répartis en quatre catégories. Le système décide où proposer le globe. Certaines applications excluent les claviers tiers et iOS reprend la main dans les champs sécurisés et téléphoniques.

Le bouton microphone dans l’extension récupère un résultat ou explique le parcours. L’extension ne lance pas l’application hôte, ne capture aucun son et n’émet aucune requête réseau. Les préférences et le transfert utilisent un App Group. Une notification interprocessus peut signaler un changement à un processus en cours d’exécution, mais elle ne garantit ni le réveil de l’application suspendue ni la disponibilité du microphone. Le parcours ne dépend donc d’aucun service vivant en arrière-plan. L’état « Clavier utilisé » est la date de dernière apparition avec accès complet. iOS ne fournit pas ici un indicateur fiable d’activation en temps réel.

Références Apple : [Création d’un clavier](https://developer.apple.com/documentation/uikit/creating-a-custom-keyboard), [guide des extensions](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/CustomKeyboard.html), [règles de distribution §4.4.1](https://developer.apple.com/app-store/review/guidelines/), [App Groups](https://developer.apple.com/documentation/xcode/configuring-app-groups).

## Moteur et modèles

whisper.cpp 1.8.2, distribution XCFramework officielle, vérifiée avant extraction. Exécution Metal sur appareil compatible et CPU sur simulateur. Le choix de whisper.cpp permet de contrôler chaque fichier téléchargé, d’utiliser des poids quantifiés et de tester le même moteur en ligne de commande. WhisperKit/Core ML constitue une autre architecture. Il n’y a pas eu de comparaison de vitesse avec WhisperKit sur iPhone. Aucun modèle n’est intégré à l’IPA. L’extension ne lie pas le moteur.

| Modèle multilingue Q5_1 | Téléchargement | Utilisation |
|---|---:|---|
| Small (par défaut) | 190 085 487 octets | Priorité à la précision |
| Base | 59 707 625 octets | Empreinte et calcul réduits |

La langue est fixée au français, traduction désactivée. Un filtre de niveau élimine les silences avant le décodage. Un second filtre exploite la probabilité d’absence de parole. Les voix faibles peuvent être rejetées et les bruits peuvent passer le filtre. Une relecture reste nécessaire, notamment pour les nombres et les noms propres.

Sources sous licence MIT : [whisper.cpp](https://github.com/ggml-org/whisper.cpp/releases/tag/v1.8.2), [poids convertis](https://huggingface.co/ggerganov/whisper.cpp/tree/c521a4b02f422512d734391fdf08bb08c0862f68), [OpenAI Whisper](https://github.com/openai/whisper). Les deux avis de licence sont inclus dans App/. Les fichiers audio de test sont des phrases originales synthétisées avec eSpeak NG en français, et un silence numérique. Ils peuvent être utilisés et redistribués avec ce projet.

## Compilation et signature

Le workflow **Open Whisper iOS** génère le projet avec XcodeGen, teste sur iPhone simulé et compile en Release pour iphoneos avec la signature désactivée. Les poids de test sont copiés uniquement dans le bundle XCTest. Le script de livraison vérifie les exécutables de l’app, de l’extension et du framework avec lipo et vtool, les identifiants, le point d’extension, les CRC de l’archive et calcule son SHA-256. Le rapport et le résultat XCTest sont publiés séparément de l’IPA. Sur Mac, les mêmes entrées sont project.yml, scripts/prepare.sh et scripts/package.sh.

1. Télécharger l’artefact **OpenWhisper-unsigned** d’une exécution réussie, extraire l’IPA et son SHA-256. Vérifier la somme avant modification.
2. Enregistrer un identifiant explicite pour l’application et un autre pour le clavier dans la même équipe Apple. Valeurs sources : **fr.openwhisper.mobile** et **fr.openwhisper.mobile.clavier**. Associer aux deux identifiants le groupe **group.fr.openwhisper.mobile**. Si ces identifiants sont indisponibles, changer les identifiants dans project.yml **et** la constante Settings.group dans Shared/Shared.swift avant recompilation.
3. Utiliser un profil de provisionnement adapté à chaque cible et contenant le même App Group. Les profils de développement ou ad hoc doivent couvrir l’iPhone cible. Dans chaque bundle, placer le profil correspondant. L’outil de signature doit appliquer les entitlements autorisés par ce profil, notamment application-identifier, équipe et com.apple.security.application-groups. Un certificat employé par les deux profils doit être disponible dans votre outil.
4. Signer le framework incorporé, puis Clavier.appex avec ses droits, puis OpenWhisper.app avec les siens. Conserver Payload/OpenWhisper.app/PlugIns/Clavier.appex dans l’IPA. Vérifier les signatures et les entitlements effectifs, puis installer via votre outil compatible avec le type de provisionnement choisi.

## Validation

Les résultats Linux et la matrice des essais figurent dans [VALIDATION.md](VALIDATION.md). Pour la compilation Apple et les XCTest, consulter le résultat et le rapport du run correspondant au commit utilisé. Les essais de microphone, d’App Group signé entre deux processus, de champs sécurisés, de bascule d’app, de suspension, de changement de route audio et de pression mémoire nécessitent une vérification sur un appareil.
