# 0. antes de tudo: o GitHub precisa ter o código (os links repository/homepage das pubspecs apontam pra lá)
git push origin main

# 1. dry-run dos quatro. Lê a lista de arquivos que cada um imprime.
tool/publish_package.sh sound_recipes --dry-run
tool/publish_package.sh voxel_engine  --dry-run
tool/publish_package.sh voxel_scene   --dry-run
tool/publish_package.sh voxel_game    --dry-run

# 2. publicação de verdade, mesma ordem (o pub pede confirmação "y" em cada um)
tool/publish_package.sh sound_recipes
tool/publish_package.sh voxel_engine
tool/publish_package.sh voxel_scene
tool/publish_package.sh voxel_game

# 3. tags (opcional, mas recomendo)
git tag voxel_engine-v0.1.0-dev && git tag sound_recipes-v0.1.0-dev \
  && git tag voxel_scene-v0.1.0-dev && git tag voxel_game-v0.1.0-dev && git push --tags
