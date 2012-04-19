" simple rdebug implementation following the execution steps ..{{{1
" this should its own ruby like plugin (TODO)

if !exists('g:rdebug') | let g:rdebug = {} | endif | let s:c = g:rdebug

command! -nargs=* AsyncRubyRDebug call rdebug#Setup(<f-args>)

sign define rdebug_current_line text=>> linehl=Type
" not used yet:
sign define rdebug_breakpoint text=O   linehl=

if !exists('*RDebugMappings')
  fun! RDebugMappings()
     noremap <F5> :call g:rdebug.ctx.write("step\n")<cr>
     noremap <F6> :call g:rdebug.ctx.write("next\n")<cr>
     noremap <F7> :call g:rdebug.ctx.write("finish\n")<cr>
     noremap <F8> :call g:rdebug.ctx.write("cont\n")|call SetCurr()<cr>
     " noremap <F9> :XDbgToggleLineBreakpoint<cr>
     " noremap \xv :XDbgVarView<cr>
     " vnoremap \xv y:XDbgVarView<cr>GpV<cr>
  endf
endif
