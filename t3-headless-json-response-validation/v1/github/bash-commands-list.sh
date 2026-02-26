# Initialiser les tests pour un nouveau projet
./Tests/Scripts/generate_headless_tests.sh

# Mettre à jour les snapshots après changement volontaire
./Tests/Scripts/update_snapshots.sh

# Vérifier les snapshots avant commit
./Tests/Scripts/verify_snapshots.sh

# Lancer les tests manuellement
vendor/bin/phpunit -c typo3/sysext/core/Build/FunctionalTests.xml Tests/Functional/Headless