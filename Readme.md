# Easygit

A git wrapper plugin made to replace [fugitive](https://github.com/tpope/vim-fugitive).
The goal is the clean code that much easier to extend, and be more friendly to
user.

## Features

* *Consist behaviour*, command always work in the git directory of current file
* *Be quiet*, no ugly *press any key to continue*, and use dispatch method when
  possible
* *Clean code*, avoid ugly hack as much as possible
* *Friendly keymaping*, when enter temporary buffer precess `q` would help you to
  quit, no close window if opened by `edit` command
* *Expose flexible API*, in `autoload/easygit.vim`
* *Works good with other plugins* since filetype is nofile, your mru plugin and
  status line plugin should easily ignore them, you can disable all comands
  with `let g:easygit_disable_command = 1` to make it works in fugitive.


## Documentation

See [doc/easygit.txt](https://github.com/chemzqm/vim-easygit/blob/master/doc/easygit.txt)
