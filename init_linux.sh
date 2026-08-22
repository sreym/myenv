#!/bin/bash

# Install nvim
# sudo add-apt-repository ppa:neovim-ppa/stable
# sudo add-apt-repository ppa:neovim-ppa/unstable
# sudo apt-get update
# sudo apt-get install neovim -y
sudo apt install snapd
sudo snap install nvim --classic
ln -s "$PWD/nvim" "$(realpath ~/.config)/nvim"

# Install zsh
sudo apt install zsh git -y
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

# Install fnm (node manager)
curl -fsSL https://fnm.vercel.app/install | bash
source /home/sergeir/.bashrc
fnm install --lts
fnm default lts-latest
fnm use lts-latest

# Install gemini-cli
npm install -g @google/gemini-cli

# Install kitty
sudo apt install kitty -y
ln -s "$PWD/kitty" "$(realpath ~/.config)/kitty"

# Install fzf
sudo apt install fzf
sed -i 's/plugins=(\([^)]*\))/plugins=(\1 fzf)/' ~/.zshrc && source ~/.zshrc

echo "source '$PWD/zshrc'" >> ~/.zshrc
source ~/.zshrc

# Install zoxide
sudo apt install zoxide -y

# Fix kitty
sudo tee /usr/local/bin/kitty << 'EOF' >/dev/null && sudo chmod +x /usr/local/bin/kitty
#!/bin/bash
export LIBGL_ALWAYS_SOFTWARE=1
exec /usr/bin/kitty "$@"
EOF

# Install firacode nerd
mkdir -p ~/.local/share/fonts/NerdFontsSymbolsOnly
curl -fLO https://github.com/ryanoasis/nerd-fonts/releases/latest/download/NerdFontsSymbolsOnly.zip
unzip -o NerdFontsSymbolsOnly.zip -d ~/.local/share/fonts/NerdFontsSymbolsOnly
rm NerdFontsSymbolsOnly.zip
fc-cache -fv

# Install batcat
sudo apt install bat

# Install tmux
ln -s "$PWD/tmux.conf" "$(realpath ~/.tmux.conf)"
