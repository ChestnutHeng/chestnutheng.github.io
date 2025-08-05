#ln -s theme.toml themes/LoveIt/config.toml
#ln -s favicon.ico themes/LoveIt/images/favicon.ico
#hugo serve --disableFastRender --theme=loveit
cp layouts/_custom.scss themes/LoveIt/assets/css/_custom.scss
hugo serve --disableFastRender -D
# enable comments
# hugo serve -e production 
