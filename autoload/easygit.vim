" ============================================================================
" Description: Functions used by easygit
" Author: Qiming Zhao <chemzqm@gmail.com>
" Licence: MIT licence
" Version: 0.1
" Last Modified:  January 4, 2016
" ============================================================================

" Extract git directory by bufffer expr use CWD as fallback
" if suspend is given as a:1, no error message
function! easygit#gitdir(buf, ...) abort
  let suspend = a:0 && a:1 != 0
  let path = fnamemodify(bufname(a:buf) , ':p')
  let gitdir = s:FindGitdir(path)
  " use current directory as fallback
  if empty(gitdir) && isdirectory(simplify(getcwd(). '/.git'))
    let gitdir = getcwd() . '/.git'
  endif
  if empty(gitdir) && !suspend
    echohl Error | echon 'Git directory not found' | echohl None
  endif
  return gitdir
endfunction

function! s:FindGitdir(path)
  let path = a:path
  while path =~# '\v/.+/'
    let dir = simplify(path . '/.git')
    if isdirectory(dir)
      return dir
    endif
    let path = substitute(path, '\v[^/]+/?$', '', '')
  endw
  return ''
endfunction

" cd or lcd to base directory
function! easygit#cd(local) abort
  let dir = easygit#gitdir('%')
  if empty(dir) | return | endif
  let cmd = a:local ? 'lcd' : 'cd'
  exe cmd . ' ' . fnamemodify(dir, ':h')
endfunction

" `cmd` string options for git checkout
" Checkout current file if cmd empty
function! easygit#checkout(cmd) abort
  let gitdir = easygit#gitdir('%')
  if empty(gitdir) | return | endif
  let root = fnamemodify(gitdir, ':h')
  let old_cwd = getcwd()
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
  execute 'silent edit! ' . expand('%:p')
endfunction

" show the commit ref with `option.edit` and `option.all`
" fold the file if `option.fold` is true
" `option.file` could contain the file for show
" `option.fold` if 0, nofold
" `option.all` show all files change
function! easygit#show(args, option) abort
  let fold = get(a:option, 'fold', 1)
  let gitdir = get(a:option, 'gitdir', easygit#gitdir('%'))
  if empty(gitdir) | return | endif
  let showall = get(a:option, 'all', 0)
  let format = '--pretty=format:''commit %H%nparent %P%nauthor %an <%ae> %ad%ncommitter %cn <%ce> %cd%n %e%n%n%s%n%n%b'' '
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
  if fold | setl fen | endif
  setlocal filetype=git foldtext=easygit#foldtext() foldmethod=syntax
  let b:gitdir = gitdir
  call setpos('.', [bufnr('%'), 7, 0, 0])
  exe 'nnoremap <buffer> <silent> u :call <SID>ShowParentCommit()<cr>'
  exe 'nnoremap <buffer> <silent> d :call <SID>ShowNextCommit()<cr>'
endfunction

function! s:ShowParentCommit() abort
  let next_commit = matchstr(getline(2), '\v\s\zs.+$')
  call easygit#show(next_commit, {
        \ 'eidt': 'edit',
        \ 'all': 1,
        \})
endfunction

function! s:ShowNextCommit() abort
  let cur_commit = matchstr(getline(1), '\v\s\zs.+$')
  let commit = s:NextCommit(cur_commit)
  if empty(commit) | return | endif
  call easygit#show(commit, {
        \ 'eidt': 'edit',
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
  let gitdir = easygit#gitdir('%')
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
  setl fen
  call setwinvar(winnr(), 'easygit_diff_origin', bnr)
  call setpos('.', [bufnr('%'), 0, 0, 0])
endfunction

" Show diff window with optional command args or `git diff`
function! easygit#diffShow(args, ...) abort
  let edit = a:0 ? a:1 : 'edit'
  let gitdir = easygit#gitdir('%')
  if empty(gitdir) | return | endif
  let root = fnamemodify(gitdir, ':h')
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

" Commit current file with message
function! easygit#commitCurrent(args) abort
  if !len(a:args)
    echohl Error | echon 'Msg should not empty' | echohl None
    return
  endif
  let gitdir = easygit#gitdir('%')
  if empty(gitdir) | return | endif
  let root = fnamemodify(gitdir, ':h')
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
  let gitdir = easygit#gitdir('%')
  if empty(gitdir) | return | endif
  let bname = bufname('%')
  let view = winsaveview()
  let root = fnamemodify(gitdir, ':h')
  let file = substitute(expand('%:p'), root . '/', '', '')
  let cmd = 'git --no-pager --git-dir=' . gitdir
      \. ' blame -- ' . expand('%:p')
  let opt = {
        \ "edit": edit,
        \ "title": '__easygit__blame__',
        \}
  let res = s:execute(cmd, opt)
  if res == -1 | return | endif
  setlocal filetype=easygitblame
  let lnum = getcurpos()[1]
  call winrestview(view)
  call s:blameHighlight()
  let b:gitdir = gitdir
  exe 'nnoremap <buffer> <silent> d :call <SID>DiffFromBlame("' . bname . '")<cr>'
  exe 'nnoremap <buffer> <silent> p :call <SID>ShowRefFromBlame("' . bname . '")<cr>'
endfunction

function! s:DiffFromBlame(bname) abort
  let commit = matchstr(getline('.'),'^\^\=\zs\x\+')
  let bnr = bufnr('%')
  let wnr = bufwinnr(a:bname)
  if wnr == -1
    execute 'silent e ' . a:bname
  else
    execute wnr . 'wincmd w'
  endif
  call easygit#diffThis(commit)
  if wnr == -1
    let b:blame_bufnr = bnr
  endif
endfunction

function! s:ShowRefFromBlame(bname) abort
  let commit = matchstr(getline('.'),'^\^\=\zs\x\+')
  let gitdir = get(b:, 'gitdir', '')
  let root = fnamemodify(gitdir, ':h')
  let file = substitute(fnamemodify(a:bname, ':p'),
      \ root . '/', '', '')
  let option = {
    \ 'edit': 'split',
    \ 'all' : 1,
    \ 'file': file,
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
  let gitdir = a:0 ? a:1 : easygit#gitdir('%')
  "if empty(gitdir) | return | endif
  let root = fnamemodify(gitdir, ':h')
  let old_cwd = getcwd()
  let edit = 'keepalt '. get(g:, 'easygit_commit_edit', 'split')
  execute 'lcd ' . root
  let cmd = 'git commit ' . a:args
  if !has('gui_running')
    noautocmd execute '!' . cmd
    execute 'lcd ' . old_cwd
  else
    let out = tempname()
    noautocmd silent execute '!env GIT_EDITOR=false ' . cmd . ' 2> ' . out
    if a:0
      let lines = readfile(out)
      if !empty(lines)
        echohl Error | echo join(lines, '\n') | echohl None
      endif
    endif
    execute 'lcd ' . old_cwd
    if !v:shell_error | return | endif
    let errors = readfile(out)
    let error = get(errors, -2, get(errors, -1, '!'))
    if error ==# '!' | echo 'nothing commit' | return | endif
    " should contain false
    if error !~# 'false''\=\.$' | return | endif
    call delete(out)
    let msgfile = gitdir . '/COMMIT_EDITMSG'
    execute edit . ' ' . fnameescape(msgfile)
    let args = a:args
    let args = s:gsub(args,'%(%(^| )-- )@<!%(^| )@<=%(-[esp]|--edit|--interactive|--patch|--signoff)%($| )','')
    let args = s:gsub(args,'%(%(^| )-- )@<!%(^| )@<=%(-c|--reedit-message|--reuse-message|-F|--file|-m|--message)%(\s+|\=)%(''[^'']*''|"%(\\.|[^"])*"|\\.|\S)*','')
    let args = s:gsub(args,'%(^| )@<=[%#]%(:\w)*','\=expand(submatch(0))')
    let args = s:sub(args, '\ze -- |$', ' --no-edit --no-interactive --no-signoff')
    let args = '-F '. msgfile . ' ' . args
    if args !~# '\%(^\| \)--cleanup\>'
      let args = '--cleanup=strip '.args
    endif
    let b:easygit_commit_arguments = args
    setlocal bufhidden=wipe filetype=gitcommit
  endif
endfunction

function! easygit#move(force, source, destination) abort
  if a:source ==# a:destination | return | endif
  let gitdir = easygit#gitdir('%')
  if empty(gitdir) | return | endif
  let root = fnamemodify(gitdir, ':h')
  let command = 'git mv ' . (a:force ? '-f ': '') . a:source . ' ' . a:destination
  let output = system(command)
  if v:shell_error && output !=# ""
    echohl Error | echon output | echohl None
    return
  endif
  let dest = substitute(a:destination, '\v^\./', '', '')
  if a:source ==# bufname('%')
    let tail = fnamemodify(bufname('%'), ':t')
    if dest ==# '.'
      exe 'keepalt edit! ' . fnameescape(tail)
    elseif isdirectory(dest)
      exe 'keepalt edit! ' . fnameescape(simplify(dest . '/'. tail))
    else
      " file name change
      exe 'keepalt saveas! ' . fnameescape(dest)
    endif
    exe 'silent! bdelete ' . bufnr(a:source)
  endif
endfunction

function! easygit#remove(force, args)
  let gitdir = easygit#gitdir('%')
  if empty(gitdir) | return | endif
  let root = fnamemodify(gitdir, ':h')
  let list = split(a:args, '\v[^\\]\zs\s')
  let files = map(filter(list, 'v:val !~# "^-"'),
    \'substitute(v:val, "^\\./", "", "")')
  let force =  a:force && a:args !~# '\v<-f>' ? '-f ' : ''
  let command = 'git rm ' . force . a:args
  let output = system(command)
  if v:shell_error && output !=# ""
    echohl Error | echon output | echohl None
    return
  endif
  let cname = substitute(expand('%'), ' ', '\\ ', 'g')
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
endfunction

function! easygit#complete(file, branch, tag)
  let root = fnamemodify(easygit#gitdir('%'), ':h')
  let output = ''
  let cwd = getcwd()
  if cwd !~ '^' .root
    exe 'lcd ' . root
  endif
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

" Execute command and show the result by options
" `option.edit` edit command used for open result buffer
" `option.pipe` pipe current buffer to command
" `option.title` requited title for the new tmp buffer
" `option.nokeep` if 1, not keepalt
function! s:execute(cmd, option) abort
  let edit = get(a:option, 'edit', 'edit')
  let pipe = get(a:option, 'pipe', 0)
  let bnr = bufnr('%')
  if edit !~# 'keepalt'
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
  let list = split(output, '\v\n')
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

function! s:NextCommit(commit) abort
  let output = system('git log --reverse --ancestry-path ' . a:commit . '..master | head -n 1 | cut -d \  -f 2')
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
  if !empty(bnr) | call easygit#blame() | endif
endfunction

function! s:sub(str,pat,rep) abort
  return substitute(a:str,'\v\C'.a:pat,a:rep,'')
endfunction

function! s:gsub(str,pat,rep) abort
  return substitute(a:str,'\v\C'.a:pat,a:rep,'g')
endfunction

" vim:set et sw=2 ts=2 tw=78:
