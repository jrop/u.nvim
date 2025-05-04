PLENARY_DIR=~/.local/share/nvim/site/pack/test/opt/plenary.nvim

all: lint test

lint:
	lua-language-server --check=lua/u/ --checklevel=Error
	lx check

fmt:
	stylua .

test: $(PLENARY_DIR)
	NVIM_APPNAME=noplugstest nvim -u NORC --headless -c 'set packpath+=~/.local/share/nvim/site' -c 'packadd plenary.nvim' -c "PlenaryBustedDirectory spec/"

$(PLENARY_DIR):
	git clone https://github.com/nvim-lua/plenary.nvim/ $(PLENARY_DIR)
