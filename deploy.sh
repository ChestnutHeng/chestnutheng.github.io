rm themes/LoveIt/assets/css/_custom.scss
cp layouts/_custom.scss themes/LoveIt/assets/css/_custom.scss
rm -rf public
hugo
cd public
git init
git branch -M master
git remote add origin git@github.com:ChestnutHeng/chestnutheng.github.io.git
git add .
git commit -m "update"
git push -u origin master -f
