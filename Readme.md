# Easygit

[![](http://img.shields.io/github/issues/neoclide/vim-easygit.svg)](https://github.com/neoclide/vim-easygit/issues)
[![](http://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![](https://img.shields.io/badge/doc-%3Ah%20easygit.txt-red.svg)](doc/easygit.txt)

A git wrapper plugin made to replace [fugitive](https://github.com/tpope/vim-fugitive),
it can be used together with fugitive as commands are disabled by default.

The goal make cleaner code, and be more friendly to user (especially using with
macvim)

## Features

* **Consist behaviour**, command always work in the git directory of current file

* **Be quiet**, no ugly **press any key to continue**, and use dispatch method when
  possible

* **Clean code**, avoid madness hack like errorformat etc.

* **Friendly keymaping**, when enter temporary buffer precess `q` would help you to
  quit, no close window if opened by `edit` command

* **Expose flexible API**, in `autoload/easygit.vim`

* **Works good with other plugins** since filetype is nofile, your mru plugin and
  status line plugin should easily ignore them.

## Commands

Commands are disabled by default, if you want to use them, you have to add

    let g:easygit_enable_command = 1

To your `.vimrc`

* *Gcd*             make vim cd to git root directory.
* *Glcd*            make vim lcd to git root directory.
* *Gblame*          Git blame current file, you can use `p` to preview commit and `d`
to diff with current file.
* *GcommitCurrent*  Git commit current file with message as command args.
* *GdiffThis*       Side by side diff of current file with head or any ref.
* *Gcommit*         Git commit with command line argument.
* *Gedit*           Edit git reference from git show.
* *Gdiff*           Git diff with command line argument.
* *Gremove*         Git remove with command line argument, remove current file
when arguments empty.
* *Grename*         Rename current by git mv, file in buffer list would react the changes.
* *Gmove*           Git mv with command line argument.
* *Gcheckout*       Git checkout with command line argument.
* *Gpush*           Git push with arguments, dispatch when possible.
* *Gpull*           Git pull with arguments, dispatch when possible.
* *Gfetch*          Git fetch with arguments, dispatch when possible.
* *Gadd*            Git add with arguments.
* *Gstatus*         Show git status in a temporary buffer.
* *Ggrep*           Git grep repo of current file, and show result in quickfix
* *Gmerge*          Git merge with branch complete

Those commands have reasonable complete setting, use `<tab>` to complete
commands.
