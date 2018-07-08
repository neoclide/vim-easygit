" ============================================================================
" Description: Functions used by easygit
" Author: Qiming Zhao <chemzqm@gmail.com>
" Licence: MIT licence
" Version: 0.2.1
" Last Modified: Dec 18, 2016
" ============================================================================
let s:nomodeline = (v:version > 703 || (v:version == 703 && has('patch442'))) ? '<nomodeline>' : ''
let s:is_win = has("win32") || has('win64')

" Extract git directory by path
" if suspend is given as a:1, no error message
function! easygit#gitdir(path, ...) abort
  let suspend = a:0 && a:1 != 0
  let path = resolve(fnamemodify(a:path , ':p'))
  let gitdir = s:FindGitdir(path)
  if empty(gitdir) && !suspend
    echohl Error | echon 'Git directory not found' | echohl None
  endif
  return gitdir
endfunction

function! s:FindGitdir(path)
  if !empty($GIT_DIR) | return $GIT_DIR | endif
  if get(g:, 'easygit_enable_root_rev_parse', 1)
    let old_cwd = getcwd()
    let cwd = fnamemodify(a:path, ':p:h')
    execute 'lcd '.cwd
    let root = system('git rev-parse --show-toplevel')
    execute 'lcd '.old_cwd
    if v:shell_error | return '' | endif
    return substitute(root, '\r\?\n', '', '') . '/.git'
  else
    let dir = finddir('.git', expand(a:path).';')
    if empty(dir) | return '' | endif
    return fnamemodify(dir, ':p:h')
  endif
endfunction

" If cwd inside current file git root, return cwd, otherwise return git root
function! easygit#smartRoot(...)
  let suspend = a:0 ? a:1 : 0
  let gitdir = easygit#gitdir(expand('%'), suspend)
  if empty(gitdir) | return '' | endif
  let root = fnamemodify(gitdir, ':h')
  let cwd = getcwd()
  return cwd =~# '^' . root ? cwd : root
endfunction


" cd or lcd to base directory of current file's git root
function! easygit#cd(local) abort
  let dir = easygit#gitdir(expand('%'))
  if empty(dir) | return | endif
  let cmd = a:local ? 'lcd' : 'cd'
  exe cmd . ' ' . fnamemodify(dir, ':h')
endfunction

" `cmd` string for git checkout
" Checkout current file if cmd empty
function! easygit#checkout(cmd) abort
  let root = easygit#smartRoot()
  if empty(root) | return | endif
  let old_cwd = getcwd()
  let view = winsaveview()
  execute 'silent lcd '. root
  if len(a:cmd)
    let command = 'git checkout ' . a:cmd
  else
    " relative path
    let file = substitute(expand('%:p'), root . '/', '', '')
    let command = 'git checkout -- ' . file
  endif
  let output = system(command)
  if v:shell_error && output !=# ''
    echohl WarningMsg | echon output | echohl None
  else
    echo 'done'
  endif
  execute 'silent lcd ' . old_cwd
  exe 'silent edit'
endfunction

" show the commit ref with `option.edit` and `option.all`
" Using gitdir of current file
" fold the file if `option.fold` is true
" `option.file` could contain the file for show
" `option.fold` if 0, not fold
" `option.all` show all files change
" `option.gitdir` could contain gitdir to work on
function! easygit#show(args, option) abort
  let fold = get(a:option, 'fold', 1)
  let gitdir = get(a:option, 'gitdir', '')
  if empty(gitdir) | let gitdir = easygit#gitdir(expand('%')) | endif
  if empty(gitdir) | return | endif
  let showall = get(a:option, 'all', 0)
  let format = "--pretty=format:'".s:escape("commit %H%nparent %P%nauthor %an <%ae> %ad%ncommitter %cn <%ce> %cd%n %e%n%n%s%n%n%b")."' "
  if showall
    let command = 'git --no-pager'
      \. ' --git-dir=' . gitdir
      \. ' show  --no-color ' . format . a:args
  else
    let root = fnamemodify(gitdir, ':h')
    let file = get(a:option, 'file',
      \substitute(expand('%:p'), root . '/', '', ''))
    let command = 'git --no-pager'
      \. ' --git-dir=' . gitdir
      \. ' show --no-color ' . format . a:args . ' -- ' . file
  endif
  let opt = deepcopy(a:option)
  let opt.title = '__easygit__show__' . s:findObject(a:args)
        \. (showall ? '' : '/' . fnamemodify(file, ':r'))
        \. '__'
  let res = s:execute(command, opt)
  if res == -1 | return | endif
  if fold | setl foldenable | endif
  setlocal filetype=git foldtext=easygit#foldtext() foldmethod=syntax
  let b:gitdir = gitdir
  call setpos('.', [bufnr('%'), 7, 0, 0])
  exe 'nnoremap <buffer> <silent> u :call <SID>ShowParentCommit()<cr>'
  exe 'nnoremap <buffer> <silent> d :call <SID>ShowNextCommit()<cr>'
endfunction

function! s:ShowParentCommit() abort
  let commit = matchstr(getline(2), '\v\s\zs.+$')
  if empty(commit) | return | endif
  call easygit#show(commit, {
        \ 'eidt': 'edit',
        \ 'gitdir': b:gitdir,
        \ 'all': 1,
        \})
endfunction

function! s:ShowNextCommit() abort
  let commit = matchstr(getline(1), '\v\s\zs.+$')
  let commit = s:NextCommit(commit, b:gitdir)
  if empty(commit) | return | endif
  call easygit#show(commit, {
        \ 'eidt': 'edit',
        \ 'gitdir': b:gitdir,
        \ 'all': 1,
        \})
endfunction

function! s:sub(str,pat,rep) abort
  return substitute(a:str,'\v\C'.a:pat,a:rep,'')
endfunction

function! s:findObject(args)
  if !len(a:args) | return 'head' | endif
  let arr = split(a:args, '\v\s+')
  for str in arr
    if str !~# '\v^-'
      return str
    endif
  endfor
  return ''
endfunction

function! easygit#foldtext() abort
    if &foldmethod !=# 'syntax'
    return foldtext()
  elseif getline(v:foldstart) =~# '^diff '
    let [add, remove] = [-1, -1]
    let filename = ''
    for lnum in range(v:foldstart, v:foldend)
      if filename ==# '' && getline(lnum) =~# '^[+-]\{3\} [abciow12]/'
        let filename = getline(lnum)[6:-1]
      endif
      if getline(lnum) =~# '^+'
        let add += 1
      elseif getline(lnum) =~# '^-'
        let remove += 1
      elseif getline(lnum) =~# '^Binary '
        let binary = 1
      endif
    endfor
    if filename ==# ''
      let filename = matchstr(getline(v:foldstart), '^diff .\{-\} a/\zs.*\ze b/')
    endif
    if filename ==# ''
      let filename = getline(v:foldstart)[5:-1]
    endif
    if exists('binary')
      return 'Binary: '.filename
    else
      return (add<10&&remove<100?' ':'') . add . '+ ' . (remove<10&&add<100?' ':'') . remove . '- ' . filename
    endif
  elseif getline(v:foldstart) =~# '^# .*:$'
    let lines = getline(v:foldstart, v:foldend)
    call filter(lines, 'v:val =~# "^#\t"')
    cal map(lines,'s:sub(v:val, "^#\t%(fixed: +|add: +)=", "")')
    cal map(lines,'s:sub(v:val, "^([[:alpha:] ]+): +(.*)", "\\2 (\\1)")')
    return getline(v:foldstart).' '.join(lines, ', ')
  endif
  return foldtext()
endfunction

" diff current file with ref in vertical split buffer
function! easygit#diffThis(ref, ...) abort
  let gitdir = easygit#gitdir(expand('%'))
  if empty(gitdir) | return | endif
  let ref = len(a:ref) ? a:ref : 'head'
  let edit = a:0 ? a:1 : 'vsplit'
  let ft = &filetype
  let bnr = bufnr('%')
  let root = fnamemodify(gitdir, ':h')
  let file = substitute(expand('%:p'), root . '/', '', '')
  let command = 'git --no-pager --git-dir='. gitdir
      \. ' show --no-color '
      \. ref . ':' . file
  let option = {
        \ "edit": edit,
        \ "title": "__easygit__file__" . ref . "_"
        \ . fnamemodify(file, ':t')
        \}
  diffthis
  let res = s:execute(command, option)
  if res == -1 | diffoff | return | endif
  execute 'setf ' . ft
  diffthis
  let b:gitdir = gitdir
  setl foldenable
  call setwinvar(winnr(), 'easygit_diff_origin', bnr)
  call setpos('.', [bufnr('%'), 0, 0, 0])
endfunction

" Show diff window with optional command args or `git diff`
function! easygit#diffShow(args, ...) abort
  let edit = a:0 ? a:1 : 'edit'
  let root = easygit#smartRoot()
  if empty(root) | return | endif
  let old_cwd = getcwd()
  execute 'silent lcd '. root
  let command = 'git --no-pager diff --no-color ' . a:args
  let options = {
        \ "edit": edit,
        \ "title": "__easygit__diff__" . s:findObject(a:args),
        \}
  let res = s:execute(command, options)
  execute 'silent lcd '. old_cwd
  if res == -1 | return | endif
  setl filetype=git foldmethod=syntax foldlevel=99
  setl foldtext=easygit#foldtext()
  call setpos('.', [bufnr('%'), 0, 0, 0])
endfunction

" Show diff content in preview window
function! easygit#diffPreview(args) abort
  let root = easygit#smartRoot()
  if empty(root) | return | endif
  let old_cwd = getcwd()
  execute 'silent lcd '. root
  let command = 'git --no-pager diff --no-color ' . a:args
  let temp = fnamemodify(tempname(), ":h") . "/" . fnamemodify(s:findObject(a:args), ':t')
  let cmd = ':silent !git --no-pager diff --no-color ' . a:args . ' > ' . temp . ' 2>&1'
   execute cmd
  execute 'silent lcd '. old_cwd
  silent execute 'pedit! ' . fnameescape(temp)
  wincmd P
  setl filetype=git foldmethod=syntax foldlevel=99
  setl foldtext=easygit#foldtext()
endfunction

" Commit current file with message
function! easygit#commitCurrent(args) abort
  if !len(a:args)
    echohl Error | echon 'Msg should not empty' | echohl None
    return
  endif
  let root = easygit#smartRoot()
  if empty(root) | return | endif
  let old_cwd = getcwd()
  execute 'silent lcd '. root
  let file = bufname('%')
  let command = 'git commit ' . file . ' -m ' . shellescape(a:args)
  let output = system(command)
  if v:shell_error && output !=# ""
    echohl Error | echon output | echohl None
  else
    echo 'done'
    execute 'silent w'
  endif
  execute 'silent lcd ' . old_cwd
endfunction

" blame current file
function! easygit#blame(...) abort
  let edit = a:0 ? a:1 : 'edit'
  let root = easygit#smartRoot()
  if empty(root) | return | endif
  let cwd = getcwd()
  " source bufnr
  let bnr = bufnr('%')
  execute 'lcd ' . root
  let view = winsaveview()
  let cmd = 'git --no-pager blame -- ' . expand('%')
  let opt = {
        \ "edit": edit,
        \ "title": '__easygit__blame__',
        \}
  let res = s:execute(cmd, opt)
  if res == -1 | return | endif
  execute 'lcd ' . cwd
  setlocal filetype=easygitblame
  call winrestview(view)
  call s:blameHighlight()
  exe 'nnoremap <buffer> <silent> d :call <SID>DiffFromBlame(' . bnr . ')<cr>'
  exe 'nnoremap <buffer> <silent> p :call <SID>ShowRefFromBlame(' . bnr . ')<cr>'
endfunction

function! s:DiffFromBlame(bnr) abort
  let commit = matchstr(getline('.'),'^\^\=\zs\x\+')
  let wnr = bufwinnr(a:bnr)
  if wnr == -1
    execute 'silent b ' . a:bnr
  else
    execute wnr . 'wincmd w'
  endif
  call easygit#diffThis(commit)
  if wnr == -1 | let b:blame_bufnr = a:bnr | endif
endfunction

function! s:ShowRefFromBlame(bnr) abort
  let commit = matchstr(getline('.'),'^\^\=\zs\x\+')
  let gitdir = easygit#gitdir(bufname(a:bnr))
  if empty(gitdir) | return | endif
  let root = fnamemodify(gitdir, ':h')
  let option = {
    \ 'edit': 'split',
    \ 'gitdir': gitdir,
    \ 'all' : 1,
    \}
  call easygit#show(commit, option)
endfunction

let s:hash_colors = {}
function! s:blameHighlight() abort
  let b:current_syntax = 'fugitiveblame'
  let conceal = has('conceal') ? ' conceal' : ''
  let arg = exists('b:fugitive_blame_arguments') ? b:fugitive_blame_arguments : ''
  syn match EasygitblameBoundary "^\^"
  syn match EasygitblameBlank                      "^\s\+\s\@=" nextgroup=EasygitblameAnnotation,fugitiveblameOriginalFile,EasygitblameOriginalLineNumber skipwhite
  syn match EasygitblameHash       "\%(^\^\=\)\@<=\x\{7,40\}\>" nextgroup=EasygitblameAnnotation,EasygitblameOriginalLineNumber,fugitiveblameOriginalFile skipwhite
  syn match EasygitblameUncommitted "\%(^\^\=\)\@<=0\{7,40\}\>" nextgroup=EasygitblameAnnotation,EasygitblameOriginalLineNumber,fugitiveblameOriginalFile skipwhite
  syn region EasygitblameAnnotation matchgroup=EasygitblameDelimiter start="(" end="\%( \d\+\)\@<=)" contained keepend oneline
  syn match EasygitblameTime "[0-9:/+-][0-9:/+ -]*[0-9:/+-]\%( \+\d\+)\)\@=" contained containedin=EasygitblameAnnotation
  exec 'syn match EasygitblameLineNumber         " *\d\+)\@=" contained containedin=EasygitblameAnnotation'.conceal
  exec 'syn match EasygitblameOriginalFile       " \%(\f\+\D\@<=\|\D\@=\f\+\)\%(\%(\s\+\d\+\)\=\s\%((\|\s*\d\+)\)\)\@=" contained nextgroup=EasygitblameOriginalLineNumber,EasygitblameAnnotation skipwhite'.(arg =~# 'f' ? '' : conceal)
  exec 'syn match EasygitblameOriginalLineNumber " *\d\+\%(\s(\)\@=" contained nextgroup=EasygitblameAnnotation skipwhite'.(arg =~# 'n' ? '' : conceal)
  exec 'syn match EasygitblameOriginalLineNumber " *\d\+\%(\s\+\d\+)\)\@=" contained nextgroup=EasygitblameShort skipwhite'.(arg =~# 'n' ? '' : conceal)
  syn match EasygitblameShort              " \d\+)" contained contains=EasygitblameLineNumber
  syn match EasygitblameNotCommittedYet "(\@<=Not Committed Yet\>" contained containedin=EasygitblameAnnotation
  hi def link EasygitblameBoundary           Keyword
  hi def link EasygitblameHash               Identifier
  hi def link EasygitblameUncommitted        Ignore
  hi def link EasygitblameTime               PreProc
  hi def link EasygitblameLineNumber         Number
  hi def link EasygitblameOriginalFile       String
  hi def link EasygitblameOriginalLineNumber Float
  hi def link EasygitblameShort              EasygitblameDelimiter
  hi def link EasygitblameDelimiter          Delimiter
  hi def link EasygitblameNotCommittedYet    Comment
  let seen = {}
  for lnum in range(1, line('$'))
    let hash = matchstr(getline(lnum), '^\^\=\zs\x\{6\}')
    if hash ==# '' || hash ==# '000000' || has_key(seen, hash)
      continue
    endif
    let seen[hash] = 1
    let s:hash_colors[hash] = ''
    exe 'syn match EasygitblameHash'.hash.'       "\%(^\^\=\)\@<='.hash.'\x\{1,34\}\>" nextgroup=EasygitblameAnnotation,EasygitblameOriginalLineNumber,fugitiveblameOriginalFile skipwhite'
  endfor
  call s:RehighlightBlame()
endfunction

function! s:RehighlightBlame() abort
  for [hash, cterm] in items(s:hash_colors)
    if !empty(cterm) || has('gui_running')
      exe 'hi EasygitblameHash'.hash.' guifg=#'.hash.get(s:hash_colors, hash, '')
    else
      exe 'hi link EasygitblameHash'.hash.' Identifier'
    endif
  endfor
endfunction

" Open commit buffer and commit changes on save
function! easygit#commit(args, ...) abort
  let gitdir = a:0 ? a:1 : easygit#gitdir(expand('%'))
  if empty(gitdir) | return | endif
  let msgfile = gitdir . '/COMMIT_EDITMSG'
  let root = a:0 > 1 ? a:2 : easygit#smartRoot()
  let old_cwd = getcwd()
  execute 'lcd ' . root
  let cmd = 'git commit ' . a:args
  if !has('gui_running') && !has('nvim')
    noautocmd execute '!' . cmd
    execute 'lcd ' . old_cwd
  else
    let out = tempname()
    noautocmd silent execute '!env GIT_EDITOR=false ' . cmd . ' 1>/dev/null 2> ' . out
    execute 'lcd ' . old_cwd
    let errors = readfile(out)
    " bufleave
    if a:0
      if !empty(errors)
        redraw
        echohl Error | echo join(errors, '\n') | echohl None
      endif
      " Wait for git to complete
      if exists('*timer_start')
        call timer_start(100, function('s:CommitCallback'))
      endif
      return
    endif
    let error = get(errors, -2, get(errors, -1, '!'))
    if error ==# '!' | call s:message('nothing to commit, working directory clean') | return | endif
    " should contain false
    if error !~# 'false''\=\.$' | return | endif
    call delete(out)
    let h = winheight(0) - 5
    execute 'silent keepalt ' . h . 'split ' . fnameescape(msgfile)
    let args = a:args
    let args = s:gsub(args,'%(%(^| )-- )@<!%(^| )@<=%(-[esp]|--edit|--interactive|--patch|--signoff)%($| )','')
    let args = s:gsub(args,'%(%(^| )-- )@<!%(^| )@<=%(-c|--reedit-message|--reuse-message|-F|--file|-m|--message)%(\s+|\=)%(''[^'']*''|"%(\\.|[^"])*"|\\.|\S)*','')
    let args = s:gsub(args,'%(^| )@<=[%#]%(:\w)*','\=expand(submatch(0))')
    let args = s:sub(args, '\ze -- |$', ' --no-edit --no-interactive --no-signoff')
    let args = '-F tmp ' . args
    if args !~# '\%(^\| \)--cleanup\>'
      let args = '--cleanup=strip '.args
    endif
    let b:easygit_commit_root = root
    let b:easygit_commit_arguments = args
    setlocal bufhidden=wipe filetype=gitcommit nofen
    return '1'
  endif
endfunction

function! s:CommitCallback(id)
  if exists('b:git_branch')
    unlet b:git_branch
  endif
  redraws!
endfunction

function! easygit#move(force, source, destination) abort
  if a:source ==# a:destination | return | endif
  let root = easygit#smartRoot()
  if empty(root) | return | endif
  let old_cwd = getcwd()
  execute 'lcd ' . root
  let source = empty(a:source) ? bufname('%') : a:source
  let command = 'git mv ' . (a:force ? '-f ': '') . source . ' ' . a:destination
  let output = system(command)
  if v:shell_error && output !=# ""
    execute 'lcd ' . old_cwd
    echohl Error | echon output | echohl None
    return
  endif
  let dest = substitute(a:destination, '\v^\./', '', '')
  if source ==# bufname('%')
    let tail = fnamemodify(bufname('%'), ':t')
    if dest ==# '.'
      exe 'keepalt edit! ' . fnameescape(tail)
    elseif isdirectory(dest)
      exe 'keepalt edit! ' . fnameescape(simplify(dest . '/'. tail))
    else
      " file name change
      exe 'keepalt saveas! ' . fnameescape(dest)
    endif
    exe 'silent! bdelete ' . bufnr(source)
  endif
  execute 'lcd ' . old_cwd
endfunction

function! easygit#remove(force, args, current)
  let root = easygit#smartRoot()
  if empty(root) | return | endif
  let old_cwd = getcwd()
  execute 'lcd ' . root
  let list = split(a:args, '\v[^\\]\zs\s')
  let files = map(filter(list, 'v:val !~# "^-"'),
    \'substitute(v:val, "^\\./", "", "")')
  let force =  a:force && a:args !~# '\v<-f>' ? '-f ' : ''
  let cname = substitute(expand('%'), ' ', '\\ ', 'g')
  if a:current | call add(files, cname) | endif
  let command = 'git rm ' . force . a:args
  let command .= a:current ? cname : ''
  let output = system(command)
  if v:shell_error && output !=# ""
    echohl Error | echon output | echohl None
    execute 'lcd ' . old_cwd
    return
  endif
  for name in files
    if name ==# cname
      if exists(':Bdelete')
        exe 'Bdelete ' . name
      else
        let alt = bufname('#')
        if !empty(alt) | execute 'e ' . alt | endif
        exe 'silent bdelete ' name
      endif
    else
      exe "silent! bdelete " . name
    endif
  endfor
  execute 'lcd ' . old_cwd
endfunction

function! easygit#complete(file, branch, tag)
  let root = easygit#smartRoot()
  let output = ''
  let cwd = getcwd()
  exe 'lcd ' . root
  if a:file
    let output .= s:system('git ls-tree --name-only -r HEAD')
  endif
  if a:branch
    let output .= s:system('git branch --no-color -a | cut -c3- | sed ''s:^remotes\/::''')
  endif
  if a:tag
    let output .= s:system('git tag')
  endif
  exe 'lcd ' . cwd
  return output
endfunction

function! easygit#completeCheckout(...)
  let root = easygit#smartRoot()
  let output = ''
  let cwd = getcwd()
  exe 'lcd ' . root
  let output .= s:system('git branch --no-color | cut -c3-')
  let output .= s:system('git ls-files -m --exclude-standard')
  exe 'lcd ' . cwd
  return output
endfunction

function! easygit#completeAdd(...)
  let root = easygit#smartRoot()
  let cwd = getcwd()
  exe 'lcd ' . root
  let output = s:system('git ls-files -m -d -o --exclude-standard')
  exe 'lcd ' . cwd
  return output
endfunction

function! easygit#completeCommit(argLead, cmdLine, curosrPos)
  let opts = ['--message', '--fixup', '--amend', '--cleanup', '--status', '--only', '-signoff']
  if a:argLead =~# '\v^-'
    return filter(opts, 'stridx(v:val,"' .a:argLead. '") == 0')
  endif
  let root = easygit#smartRoot()
  let cwd = getcwd()
  exe 'lcd ' . root
  let output = s:system('git status -s|cut -c 4-')
  exe 'lcd ' . cwd
  if !empty(output)
    let files = split(output, '\n')
    return filter(files, 'stridx(v:val,"' .a:argLead. '") == 0')
  endif
  return []
endfunction

function! easygit#completeReset(argLead, ...)
  let opts = ['--soft', '--hard', '--merge', '--keep', '--mixed']
  if a:argLead =~# '\v^-'
    return filter(opts, 'stridx(v:val,"' .a:argLead. '") == 0')
  endif
  let root = easygit#smartRoot()
  let cwd = getcwd()
  exe 'lcd ' . root
  let output = s:system('git diff --staged --name-status | cut -f 2')
  exe 'lcd ' . cwd
  if !empty(output)
    let files = split(output, '\n')
    return filter(files, 'stridx(v:val,"' .a:argLead. '") == 0')
  endif
  return []
endfunction

function! easygit#completeRevert(argLead, ...)
  let opts = ['--continue', '--quit', '--abort']
  if a:argLead =~# '\v^-'
    return filter(opts, 'stridx(v:val,"' .a:argLead. '") == 0')
  endif
  return []
endfunction

function! easygit#listRemotes(...)
  let root = easygit#smartRoot()
  if empty(root) | return | endif
  let cwd = getcwd()
  exe 'lcd ' . root
  let output = s:system('git branch -r | sed ''s:/.*::''|uniq')
  exe 'lcd ' . cwd
  return substitute(output, '\v(^|\n)\zs\s*', '', 'g')
endfunction

function! easygit#revert(args)
  let root = easygit#smartRoot()
  if empty(root) | return | endif
  let cwd = getcwd()
  execute 'lcd ' . root
  call s:system('git revert ' . a:args)
  execute 'lcd ' . cwd
endfunction

function! easygit#reset(args)
  let root = easygit#smartRoot()
  if empty(root) | return | endif
  let cwd = getcwd()
  execute 'lcd ' . root
  call s:system('git reset ' . a:args)
  execute 'lcd ' . cwd
endfunction

" Run git add with files in smartRoot
function! easygit#add(...) abort
  let root = easygit#smartRoot()
  if empty(root) | return | endif
  let cwd = getcwd()
  execute 'lcd ' . root
  if empty(a:000)
    let l:args = expand('%')
  else
    let l:args = join(map(copy(a:000), 'shellescape(v:val)'), ' ')
  endif
  let command = 'git add ' . l:args
  call s:system(command)
  call s:ResetGutter(bufnr('%'))
  execute 'lcd ' . cwd
endfunction

" Open git status buffer from smart root
function! easygit#status()
  let root = easygit#smartRoot()
  if empty(root) | return | endif
  let cwd = getcwd()
  execute 'lcd ' . root
  call s:execute('git --no-pager status --long -b', {
        \ 'edit': 'edit',
        \ 'title': '__easygit_status__',
        \})
  execute 'lcd ' . cwd
endfunction

function! easygit#read(args)
  let root = easygit#smartRoot()
  if empty(root) | return | endif
  let old_cwd = getcwd()
  execute 'lcd ' . root
  if empty(a:args)
    let path = expand('%')
  else
    let path = a:args
  endif
  if empty(path) | return | endif
  let output = system('git --no-pager show :'.path)
  if v:shell_error && output !=# ""
    echohl Error | echon output | echohl None
    return -1
  endif
  let save_cursor = getcurpos()
  execute 'edit ' . path
  execute '%d'
  let eol = s:is_win ? '\v\n' : '\v\r?\n'
  let list = split(output, eol)
  if len(list)
    call setline(1, list[0])
    silent! call append(1, list[1:])
  endif
  call setpos('.', save_cursor)
  call s:ResetGutter(bufnr(path))
  execute 'lcd ' . old_cwd
endfunction

function! easygit#merge(args)
  if a:0 == 0 | return | endif
  let root = easygit#smartRoot()
  if empty(root) | return | endif
  let cwd = getcwd()
  execute 'lcd ' . root
  let command = 'git merge ' . a:args
  call s:system(command)
  execute 'lcd ' . cwd
endfunction

function! easygit#grep(args)
  let root = easygit#smartRoot()
  if empty(root) | return | endif
  let cwd = getcwd()
  execute 'lcd ' . root
  let old_grepprg = &grepprg
  let old_grepformat = &grepformat
  set grepprg=git\ --no-pager\ grep\ --no-color\ -n\ $*
  set grepformat=%f:%l:%m
  execute 'silent grep ' . a:args
  if get(g:, 'easygit_grep_open', 1)
    cwindow
  endif
  let &grepprg = old_grepprg
  let &grepformat = old_grepformat
endfunction

" Execute command and show the result by options
" `option.edit` edit command used for open result buffer
" `option.pipe` pipe current buffer to command
" `option.title` required title for the new tmp buffer
" `option.nokeep` if 1, not keepalt
function! s:execute(cmd, option) abort
  let edit = get(a:option, 'edit', 'edit')
  let pipe = get(a:option, 'pipe', 0)
  let bnr = bufnr('%')
  if edit ==# 'pedit'
    let edit = 'new +setlocal\ previewwindow'
  endif
  if edit !~# 'keepalt' && !get(a:option, 'nokeep', 0)
    let edit = 'keepalt ' . edit
  endif
  if pipe
    let stdin = join(getline(1, '$'),"\n")
    let output = system(a:cmd, stdin)
  else
    let output = system(a:cmd)
  endif
  if v:shell_error && output !=# ""
    echohl Error | echon output | echohl None
    return -1
  endif
  execute edit . ' ' . a:option.title
  exe 'nnoremap <buffer> <silent> q :call <SID>SmartQuit("' . edit . '")<cr>'
  let b:easygit_prebufnr = bnr
  let eol = s:is_win ? '\v\n' : '\v\r?\n'
  let list = split(output, eol)
  if len(list)
    call setline(1, list[0])
    silent! call append(1, list[1:])
  endif
  setlocal buftype=nofile readonly bufhidden=wipe
endfunction

function! s:system(command)
  let output = system(a:command)
  if v:shell_error && output !=# ""
    echohl Error | echon output | echohl None
    return ''
  endif
  return output
endfunction

function! s:NextCommit(commit, gitdir) abort
  let output = system('git --git-dir=' . a:gitdir
        \. ' log --reverse --ancestry-path '
        \. a:commit . '..master | head -n 1 | cut -d \  -f 2')
  if v:shell_error && output !=# ""
    echohl Error | echon output | echohl None
    return
  endif
  return substitute(output, '\n', '', '')
endfunction

function! s:SmartQuit(edit)
  let bnr = get(b:, 'blame_bufnr', '')
  if a:edit =~# 'edit'
    try
      exe 'b ' . b:easygit_prebufnr
    catch /.*/
      exe 'q'
    endtry
  else
    exe 'q'
  endif
  if !empty(bnr)
    call easygit#blame()
  endif
endfunction

function! s:sub(str,pat,rep) abort
  return substitute(a:str,'\v\C'.a:pat,a:rep,'')
endfunction

function! s:gsub(str,pat,rep) abort
  return substitute(a:str,'\v\C'.a:pat,a:rep,'g')
endfunction

function! s:message(msg)
  echohl MoreMsg | echon a:msg | echohl None
endfunction

function! easygit#dispatch(name, args)
  let root = easygit#smartRoot()
  if empty(root) | return | endif
  let cwd = getcwd()
  let cmd = 'git ' . a:name . ' ' . a:args
  if !has('gui_running')
    let pre = exists(':Nrun') ? 'Nrun ' : '!'
    if has('nvim') && pre ==# '!'
      let pre = ':terminal '
    endif
    exe 'lcd ' . root
    exe pre . cmd
    exe 'nnoremap <buffer> <silent> q :bd!<cr>'
    exe 'lcd ' . cwd
  else
    let title = 'easygit-' . a:name
    if exists(':Start')
      exe 'Start! -title=' . title . ' -dir=' . root
          \. ' ' . cmd
    elseif exists(':ItermStartTab')
      exe 'ItermStartTab! -title=' . title . ' -dir=' . root
          \. ' ' . cmd
    else
      exe '!' . cmd
    endif
  endif
endfunction

function! s:winshell() abort
  return &shell =~? 'cmd' || exists('+shellslash') && !&shellslash
endfunction

function! s:escape(str)
  if s:winshell()
    let cmd_escape_char = &shellxquote == '(' ?  '^' : '^^^'
    return substitute(a:str, '\v\C[<>]', cmd_escape_char, 'g')
  endif
  return a:str
endfunction

function! s:ResetGutter(bufnr)
  if exists('*gitgutter#process_buffer')
    call gitgutter#process_buffer(a:bufnr, 1)
  endif
endfunction
" vim:set et sw=2 ts=2 tw=78:
