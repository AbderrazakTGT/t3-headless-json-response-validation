# 1. Cloner les scripts dans votre projet
mkdir -p Tests/Scripts
cp generate_headless_tests.sh Tests/Scripts/
cp update_snapshots.sh Tests/Scripts/
cp verify_snapshots.sh Tests/Scripts/
chmod +x Tests/Scripts/*.sh

# 2. Créer la configuration CI
cp .gitlab-ci.yml .gitlab-ci.yml