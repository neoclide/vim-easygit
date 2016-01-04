if exists('did_easygit_loaded') || v:version < 700
  finish
endif
let did_easygit_loaded = 1

function! s:FinishCommit() abort
  let args = getbufvar(+expand('<abuf>'),'easygit_commit_arguments')
  if !empty(args)
    call setbufvar(+expand('<abuf>'),'easygit_commit_arguments','')
    let gitdir = fnamemodify(bufname(+expand('<abuf>')), ':p:h')
    return easygit#commit(args, gitdir)
  endif
endfunction

function! s:Edit(args)
  let option = {
        \ "all": 1,
        \ "edit": get(g:, 'easygit_edit_command', 'edit'),
        \ "fold": get(g:, 'easygit_edit_fold', 1),
        \}
  call easygit#show(a:args, option)
endfunction

function! s:DiffShow(args)
  let edit = get(g:, 'easygit_diff_edit', 'edit')
  call easygit#diffShow(a:args, edit)
endfunction

function! s:CommitAll()
  let arg = ' -a -v'
  call easygit#commit(arg)
endfunction

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
  let g:val = val
  let wnr = bufwinnr(val)
  if wnr > 0
    exe wnr . "wincmd w"
    diffoff
  endif
endfunction

function! s:DiffThis(arg)
  let ref = len(a:arg) ? a:arg : 'head'
  let edit = get(g:, 'easygit_diff_this_edit', 'vsplit')
  call easygit#diffThis(ref, edit)
endfunction

augroup easygit
  autocmd!
  autocmd VimLeavePre,BufDelete COMMIT_EDITMSG call s:FinishCommit()
  autocmd BufWinLeave * call s:Onbufleave()
augroup END

" TODO use user complete from git ls
if !get(g:, 'easygit_disable_command', 0)
  command! -nargs=0 Gcd                      :call easygit#cd(0)
  command! -nargs=0 Glcd                     :call easygit#cd(1)
  command! -nargs=* -complete=file Gco       :call easygit#checkout(<q-args>)
  command! -nargs=* -complete=file Gedit     :call s:Edit(<q-args>)
  command! -nargs=* Gdiff                    :call s:DiffShow(<q-args>)
  command! -nargs=+ Gci                      :call easygit#commitCurrent(<q-args>)
  command! -nargs=0 Gca                      :call s:CommitAll()
  command! -nargs=+ Gcommit                  :call easygit#commit(<q-args>)
  command! -nargs=? GdiffThis                :call s:DiffThis(<q-args>)
  command! -nargs=0 Gblame                   :call easygit#blame()
endif
