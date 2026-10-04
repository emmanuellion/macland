# Island

Une « Dynamic Island » pour l'encoche des MacBook, inspirée d'Alcove et NotchBox.
Tout est configurable : chaque module s'active, se réordonne et se règle depuis la fenêtre de réglages.

## Modules

- **Lecture en cours** : pochette, contrôles, barre de progression déplaçable, choix de la sortie audio.
- **Date & heure**, **Batterie**, **Calendrier** (désactivé par défaut).
- **Presse-papiers** : historique texte / images / fichiers, épinglage, raccourci global (⌃⌘V par défaut).
- **Étagère** : dépôt de fichiers sur l'encoche, AirDrop, compression .zip, conversion d'images.
- **Volume & luminosité** : remplace le HUD de macOS par une jauge dans l'encoche.
- **Caméra & micro** : indicateurs à côté de l'encoche pendant l'utilisation.
- **Activités en direct** : infos brèves autour de l'encoche fermée (charge, rappels, lecture…).

## Compiler

Aucun compte développeur Apple nécessaire, Xcode non requis (Command Line Tools suffisent).

```sh
scripts/build-app.sh --run            # compile build/Island.app et la lance
scripts/build-app.sh --install --run  # installe dans ~/Applications (lancement au démarrage)
```

Le script signe avec le certificat « Island Local Signing » s'il est présent dans le trousseau
(les permissions macOS sont alors conservées d'une compilation à l'autre), sinon en ad-hoc.

## Notes

- La lecture en cours passe par [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter)
  (BSD-3, copié dans `Vendor/`) : depuis macOS 15.4, seul un binaire Apple peut lire MediaRemote.
- Le HUD (mode « Remplacer ») demande la permission Accessibilité ; la luminosité utilise
  le framework privé DisplayServices.
- Requiert macOS 15 ou plus récent.
