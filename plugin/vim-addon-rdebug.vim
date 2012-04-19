" simple rdebug implementation following the execution steps ..{{{1
" this should its own ruby like plugin (TODO)

if !exists('g:rdebug') | let g:rdebug = {} | endif | let s:c = g:rdebug

command! -nargs=* AsyncRubyRDebug call rdebug#Setup(<f-args>)

sign define rdebug_current_line text=>> linehl=Type
" not used yet:
sign define rdebug_breakpoint text=O   linehl=

if !exists('*RDebugMappings')
  fun! RDebugMappings()
     noremap <F5> :call rdebug#Debugger("step")<cr>
     noremap <F6> :call rdebug#Debugger("next")<cr>
     noremap <F7> :call rdebug#Debugger("finish")<cr>
     noremap <F8> :call rdebug#Debugger("cont")<cr>
     noremap <F9> :call rdebug#Debugger("toggle_break_point")<cr>
     " noremap \xv :XDbgVarView<cr>
     " vnoremap \xv y:XDbgVarView<cr>GpV<cr>
  endf
endif
