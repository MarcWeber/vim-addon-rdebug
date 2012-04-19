" exec vam#DefineAndBind('s:c','g:rdebug','{}')
if !exists('g:rdebug') | let g:rdebug = {} | endif | let s:c = g:rdebug

" You can also run /bin/sh and use require 'debug' in your ruby scripts

fun! rdebug#Setup(...)
  if a:0 > 0
    " TODO quoting?
    let cmd = join(a:000," ")
  else
    let cmd = input('ruby command:')
  endif
  let g:rdebug.ctx = rdebug#RubyBuffer({'cmd': 'socat "EXEC:'.cmd.',pty,stderr" -', 'move_last' : 1})
  call RDebugMappings()
endf

fun! rdebug#RubyBuffer(...)
  let ctx = a:0 > 0 ? a:1 : {}
  call async_porcelaine#LogToBuffer(ctx)
  let ctx.receive = function('rdebug#Receive')
  return ctx
endf

fun! rdebug#Receive(...) dict
  call call(function('async_porcelaine#Receive2'), a:000, self)
endf
fun! async_porcelaine#Receive2(...) dict
  let self.received_data = get(self,'received_data','').a:1
  let lines = split(self.received_data,"\n",1)

  let feed = []
  let s = ""
  " process complete lines
  for l in lines[0:-2]
    let m = matchlist(l, '^\([^:]\+\):\(\d\+\):')
    if len(m) > 0 && m[1] != ''
      if filereadable(m[1])
        call rdebug#SetCurr(m[1], m[2])
      endif
    endif
    let s .= l."\n"
  endfor
  " keep rest of line
  let self.received_data = lines[-1]

  if len(s) > 0
    call async#DelayUntilNotDisturbing('process-pid'. self.pid, {'delay-when': ['buf-invisible:'. self.bufnr], 'fun' : self.delayed_work, 'args': [s, 1], 'self': self} )
  endif
endf

" SetCurr() (no debugging active
" SetCurr(file, line)
" mark that line as line which will be executed next
fun! rdebug#SetCurr(...)
  if a:0 == 0
    call vim_addon_signs#Push("rdebug_current_line", [] )
  else
    call buf_utils#GotoBuf(a:1, {'create':1})
    exec a:2
    " exec a:2
    call vim_addon_signs#Push("rdebug_current_line", [[bufnr(a:1), a:2, "rdebug_current_line"]] )
    " call rdebug#UpdateVarView()
  endif
endf

" AsyncRubyRDebug ruby retro_games.rb
