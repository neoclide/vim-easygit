if exists('g:did_easygit_loaded') || v:version < 700
  finish
endif
let g:did_easygit_loaded = 1

function! s:FinishCommit() abort
  if !has('gui_running') && !has('nvim') | return | endif
  let args = getbufvar(+expand('<abuf>'),'easygit_commit_arguments')
  if !empty(args)
    call setbufvar(+expand('<abuf>'),'easygit_commit_arguments','')
    let gitdir = fnamemodify(bufname(+expand('<abuf>')), ':p:h')
    " cat current file content to tmpfile
    let out = tempname()
    call system('cat ' . fnamemodify(bufname(+expand('<abuf>')), ':p'). '> ' . out)
    let args = substitute(args, '\v\s-F\stmp', ' -F ' . out, '')
    let root = getbufvar(+expand('<abuf>'),'easygit_commit_root')
    return easygit#commit(args, gitdir, root)
  endif
endfunction

function! s:Edit(args)
  let option = {
        \ "all": 1,
        \ "edit": get(g:, 'easygit_edit_edit_command', 'edit'),
        \ "fold": get(g:, 'easygit_edit_fold', 1),
        \}
  call easygit#show(a:args, option)
endfunction

function! s:DiffShow(args)
  let edit = get(g:, 'easygit_diff_edit_command', 'edit')
  call easygit#diffShow(a:args, edit)
endfunction

" Restore diff status if no diff buffer open
function! s:Onbufleave()
  let wnr = +bufwinnr(+expand('<abuf>'))
  let val = getwinvar(wnr, 'easygit_diff_origin')
  if !len(val) | return | endif
  for i in range(1, winnr('$'))
    if i == wnr | continue | endif
    if len(getwinvar(i, 'easygit_diff_origin'))
      return
    endif
  endfor
  let wnr = bufwinnr(val)
  if wnr > 0
    exe wnr . "wincmd w"
    diffoff
  endif
endfunction

function! s:Move(...)
  if a:0 != 3
    echohl Error | echon 'Gmove requires source and destination' | echohl None
    return
  endif
  let bang = a:1 ==# '!' ? 1 : 0
  call easygit#move(bang, a:2, a:3)
endfunction

function! s:Rename(bang, destination)
  let force = a:bang ==# '!' ? 1 : 0
  call easygit#move(force, '', a:destination)
endfunction

function! s:DiffThis(arg)
  let ref = len(a:arg) ? a:arg : 'head'
  let edit = get(g:, 'easygit_diff_this_edit', 'vsplit')
  call easygit#diffThis(ref, edit)
endfunction

function! s:Remove(bang, ...)
  let force = a:bang ==# '!' ? 1 : 0
  " keep the \ for space
  let list = map(copy(a:000), 'substitute(v:val, " ", "\\\\ ", "")')
  let files = filter(copy(list), 'v:val !~# "^-"')
  let current = empty(files)
  call easygit#remove(force, join(list, ' '), current)
endfunction

function! s:GitFiles(A, L, P)
  return easygit#complete(1, 0, 0)
endfunction

function! s:TryGitCd(type)
  if !empty(&buftype) | return | endif
  if expand('%') =~# '^\w\+://' | return | endif
  if &previewwindow | return | endif
  let gitdir = easygit#gitdir(expand('%'), 1)
  if empty(gitdir)
    if exists('w:original_cwd') && stridx(expand('%:p'), w:original_cwd) == 0
      exe a:type . ' ' . w:original_cwd
    endif
    return
  endif
  let root = fnamemodify(gitdir, ':h')
  let cwd = getcwd()
  if stridx(cwd, root) != 0
    let w:original_cwd = cwd
    exe a:type . ' ' . root
  endif
endfunction

" Tag and Branch
function! s:CompleteCheckout(A, L, P)
  return easygit#completeCheckout()
endfunction

function! s:CompleteBranch(A, L, P)
  return easygit#complete(0, 1, 0)
endfunction

" Branch
function! s:CompleteShow(A, L, P)
  return easygit#complete(0, 1, 0)
endfunction

" File and Branch
function! s:CompleteDiffThis(A, L, P)
  return easygit#complete(1, 1, 0)
endfunction

function! s:CommitCurrent(args)
  if empty(a:args)
    let root = easygit#smartRoot()
    if empty(root) | return | endif
    let file = substitute(expand('%:p'), root . '/', '', '')
    call easygit#commit(' -v -- ' . file)
  else
    call easygit#commitCurrent(a:args)
  endif
endfunction

augroup easygit
  autocmd!
  autocmd VimLeavePre,BufDelete COMMIT_EDITMSG call s:FinishCommit()
  autocmd BufWinLeave __easygit__file* call s:Onbufleave()
augroup END

if get(g:, 'easygit_enable_command', 0)
  command! -nargs=0 Gcd                            :call easygit#cd(0)
  command! -nargs=0 Glcd                           :call easygit#cd(1)
  command! -nargs=0 Gblame                         :call easygit#blame()
  command! -nargs=0 Gstatus                        :call easygit#status()
  command! -nargs=* GcommitCurrent                 :call s:CommitCurrent(<q-args>)
  command! -nargs=? -complete=custom,s:CompleteDiffThis  GdiffThis  :call s:DiffThis(<q-args>)
  command! -nargs=* -complete=custom,s:GitFiles          Ggrep      :call s:Remove('<bang>', <f-args>)
  command! -nargs=* -complete=custom,s:CompleteShow      Gedit      :call s:Edit(<q-args>)
  command! -nargs=* -complete=custom,s:CompleteBranch    Gdiff      :call s:DiffShow(<q-args>)
  command! -nargs=* -bang -complete=custom,s:GitFiles    Gremove    :call s:Remove('<bang>', <f-args>)
  command! -nargs=1 -bang -complete=custom,s:GitFiles    Grename    :call s:Rename('<bang>', <f-args>)
  command! -nargs=+ -bang -complete=custom,s:GitFiles    Gmove      :call s:Move('<bang>', <f-args>)
  command! -nargs=* -complete=custom,s:CompleteCheckout  Gcheckout  :call easygit#checkout(<q-args>)
  command! -nargs=* -complete=custom,easygit#listRemotes Gpush      :call easygit#dispatch('push', <q-args>)
  command! -nargs=* -complete=custom,easygit#listRemotes Gfetch     :call easygit#dispatch('fetch', <q-args>)
  command! -nargs=* -complete=custom,easygit#listRemotes Gpull      :call easygit#dispatch('pull', <q-args>)
  command! -nargs=* -complete=custom,easygit#completeAdd Gadd       :call easygit#add(<f-args>)
  command! -nargs=+ -complete=custom,s:CompleteBranch    Gmerge     :call easygit#merge(<q-args>)
  command! -nargs=+ -complete=custom,s:GitFiles          Ggrep      :call easygit#grep(<q-args>)
  command! -nargs=+ -complete=customlist,easygit#completeRevert    Grevert    :call easygit#revert(<q-args>)
  command! -nargs=+ -complete=customlist,easygit#completeReset     Greset     :call easygit#reset(<q-args>)
  command! -nargs=+ -complete=customlist,easygit#completeCommit    Gcommit    :call easygit#commit(<q-args>)
  command! -nargs=? -complete=custom,easygit#completeAdd           Gread      :call easygit#read(<q-args>)
endif

" enable auto lcd
augroup easygit_auto_lcd
  autocmd!
  if get(g:, 'easygit_auto_lcd', 0)
    autocmd BufWinEnter,BufReadPost * call s:TryGitCd('lcd')
  elseif get(g:, 'easygit_auto_tcd', 0) && exists(':tcd') == 2
    autocmd BufWinEnter,BufReadPost * call s:TryGitCd('tcd')
  endif
augroup end

"vim:set et sw=2 ts=2 tw=80 foldmethod=syntax fen:
