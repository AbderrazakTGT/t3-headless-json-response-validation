# Changement volontaire du JSON
git checkout -b feature/add-difficulty-field

# Modifier le code...
# Mettre à jour les snapshots
./Tests/Scripts/update_snapshots.sh

# Vérifier
./Tests/Scripts/verify_snapshots.sh

# Commit et push
git add Tests/Fixtures/Snapshots/
git commit -m "feat: add difficulty field to courses"
git push origin feature/add-difficulty-field