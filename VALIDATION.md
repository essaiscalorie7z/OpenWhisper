# Validation des parcours

## Essais réalisés sous Linux x86_64

Compilation native de whisper.cpp au commit 4979e04f5dcaccb36057e059bbaed8a2f5288315 (v1.8.2, CMake/Ninja, OpenMP désactivé). Téléchargement des deux poids depuis la révision épinglée et comparaison SHA-256 réussie. Exécution locale de whisper-cli sur les trois WAV de Tests/Fixtures, avec quatre threads et langue fr. La commande de référence est `whisper-cli -m MODELE -l fr -t 4 -f FICHIER.wav`. Les poids ont été lus depuis le disque. Aucun appel de transcription à un service.

| Échantillon | Référence | Base Q5_1 | Small Q5_1 |
|---|---|---|---|
| court | Bonjour, je suis à Paris. | Je suis ma paille. | Poutou, je suis à Paris ! |
| long | Demain matin, je prendrai le train pour Lyon. Est-ce que tu peux apporter le dossier que nous avons préparé ensemble ? | de ma mata, je parlerai de ma bouleau, est-ce que tu peux m'apporter le dossier que nous avons préparé ensemble? | Demain matin, je parlerai le temps pour vous. Est-ce que tu peux m'apporter le dossier que nous avons préparé ensemble? |
| silence, sans filtre applicatif | silence numérique, 3 secondes | ... | Sous-titres réalisés par la communauté d’Amara.org |

WER micro-moyenné sur 26 mots de référence, distance de Levenshtein après passage en minuscules et séparation sur la ponctuation (trait d’union inclus) : Base **12/26 = 46,2 %**, Small **5/26 = 19,2 %**. Il s’agit de deux échantillons de voix synthétique eSpeak NG, insuffisants pour prédire la précision sur une voix humaine. Temps totaux du moteur sur ces deux clips : Base 2,26 et 2,44 s ; Small 6,79 et 7,53 s. Ces chiffres sont ceux du CPU Linux de développement. Le téléchargement de l’XCFramework officiel a été vérifié par SHA-256 ; inspection de sa tranche iphoneos : bibliothèque dynamique Mach-O arm64.

## Tests Apple du workflow

* Le test du moteur charge le même modèle Base dans l’application de test, décode les deux fichiers et vérifie le rejet du silence par le filtre applicatif.
* Les tests de clavier activent les boutons du véritable contrôleur UIKit avec un proxy de document de test : alphabet, chiffre, symbole, espace, emoji, catégorie, suppression, retour, verrouillage des majuscules, présence d’une variante accentuée, suggestion et aide du microphone sans accès complet. Le sélecteur de clavier d’iOS et le geste physique d’appui long ne sont pas automatisés par ce test.
* Les tests du conteneur vérifient la publication, la consommation unique et l’effacement dans un répertoire temporaire. Le partage avec signature et droits système se vérifie séparément.
* Le succès de chaque exécution est indiqué dans GitHub Actions. Une étape écrite dans le workflow ne vaut pas résultat de test.

## Recette sur iPhone signé

| Parcours à vérifier | Résultat attendu |
|---|---|
| Installation sur appareil, clavier activé sans accès complet | Frappe AZERTY, symboles, accents, emojis, changement de clavier et aide du microphone disponibles. |
| Modèle absent, manque de stockage, réseau interrompu | Clavier ordinaire disponible ; erreur explicite et nouvel essai dans l’application. |
| Micro refusé puis autorisé | Réglages proposés après refus ; capture seulement pendant la dictée au premier plan. |
| Appel, verrouillage, mise en arrière-plan, glissement d’annulation | Arrêt du microphone, suppression du fichier temporaire et absence de publication automatique. |
| Publication puis bascule vers Notes ou Messages, accès complet activé | Un toucher insère dans le champ actif ; un second toucher ne répète pas l’insertion. |
| App suspendue ou terminée après publication | Récupération du texte déjà partagé tant qu’il est valide et que le conteneur est accessible. |
| Mot de passe, numéro de téléphone, hôte refusant le clavier | Respect de la sélection du clavier système par iOS. |
| Mode Avion après installation, voix faibles, noms propres, phrases longues | Mesurer erreurs, latence, mémoire, batterie et acceptabilité pour chaque modèle et appareil. |
