" exec vam#DefineAndBind('s:c','g:rdebug','{}')
if !exists('g:rdebug') | let g:rdebug = {} | endif | let s:c = g:rdebug
let s:c.ctxs = {}
let s:c.next_ctx_nr = get(s:c, 'ctx_nr', 1)

" You can also run /bin/sh and use require 'debug' in your ruby scripts

fun! rdebug#Setup(...)
  if a:0 > 0
    " TODO quoting?
    let cmd = join(a:000," ")
  else
    let cmd = input('ruby command:')
  endif
  let ctx = rdebug#RubyBuffer({'cmd': 'socat "EXEC:'.cmd.',pty,stderr" -', 'move_last' : 1})
  let ctx.ctx_nr = s:c.next_ctx_nr
  let ctx.vim_managed_breakpoints = []
  let ctx.next_breakpoint_nr = 1
  let s:c.ctxs[s:c.next_ctx_nr] = ctx
  let s:c.active_ctx = s:c.next_ctx_nr
  let s:c.next_ctx_nr = 1
  call RDebugMappings()
  call rdebug#UpdateBreakPoints()
endf

fun! rdebug#RubyBuffer(...)
  let ctx = a:0 > 0 ? a:1 : {}

  fun ctx.terminated()
    call append('$','END')
    if has_key(self, 'curr_pos')
      unlet self.curr_pos
    endif
    call rdebug#SetCurr()
  endf

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
        let self.curr_pos = {'filename':m[1], 'line': m[2]}
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
  " list of all current execution points of all known ruby processes
  let curr_poss = []

  for [k,v] in items(s:c.ctxs)
    " process has finished? no more current lines
    if has_key(v, 'curr_pos')
      let cp = v.curr_pos
      let buf_nr = bufnr(cp.filename)
      if (buf_nr == -1)
        exec 'sp '.fnameescape(cp.filename)
        let buf_nr = bufnr(cp.filename)
      endif
      call add(curr_poss, [buf_nr, cp.line, "rdebug_current_line"])
    endif
    unlet k v
  endfor

  " jump to new execution point
  if a:0 != 0
    call buf_utils#GotoBuf(a:1, {'create_cmd': 'sp'})
    exec a:2
    " exec a:2
    " call rdebug#UpdateVarView()
  endif
  call vim_addon_signs#Push("rdebug_current_line", curr_poss )
endf

fun! rdebug#Debugger(cmd, ...)
  let ctx_nr = a:0 > 0 ? a:1 : s:c.active_ctx
  let ctx = s:c.ctxs[ctx_nr]
  if a:cmd =~ '\%(step\|next\|finish\|cont\)'
    call ctx.write(a:cmd."\n")
    if a:cmd == 'cont'
      unlet ctx.curr_pos
      call rdebug#SetCurr()
    endif
  elseif a:cmd == 'toggle_break_point'
    call rdebug#ToggleLineBreakpoint()
  else
    throw "unexpected command
  endif
endf

let s:auto_break_end = '== break points end =='
fun! rdebug#BreakPointsBuffer()
  let buf_name = "XDEBUG_BREAK_POINTS_VIEW"
  let cmd = buf_utils#GotoBuf(buf_name, {'create':1} )
  if cmd == 'e'
    " new buffer, set commands etc
    let s:c.var_break_buf_nr = bufnr('%')
    noremap <buffer> <cr> :call rdebug#UpdateBreakPoints()<cr>
    call append(0,['# put the breakpoints here, prefix with # to deactivate:', s:auto_break_end
          \ , 'rdebug supports different types of breakpoints:'
          \ , '[file:|class:]<line|method>'
          \ , '[class.]<line|method>'
          \ , 'you always have to add the file / class in Vim'
          \ , 'hit <cr> to send updated breakpoints to processes'
          \ ])
    " it may make sense storing breakpoints. So allow writing the breakpoints
    " buffer
    " set buftype=nofile
  endif

  let buf_nr = bufnr(buf_name)
  if buf_nr == -1
    exec 'sp '.fnameescape(buf_name)
  endif
endf


fun! rdebug#UpdateBreakPoints()
  let signs = []
  let points = []
  let dict_new = {}
  call rdebug#BreakPointsBuffer()

  let r_line        = '^\([^:]\+\):\(.*\)$'
  let r_class_method     = '^\([^:]\+\)\.\([^:]\+\)$'

  for l in getline('0',line('$'))
    if l =~ s:auto_break_end | break | endif
    if l =~ '^#' | continue | endif
    silent! unlet args
    let condition = ""

    let m = matchlist(l, r_line)
    if !empty(m)
      let point = {}
      if (filereadable(m[1]))
        let point['file'] = m[1]
      else
        let point['class'] = m[1]
      endif
      " ruby does not allow numbers to be methods
      if m[2] =~ '^\d\+$'
        let point['line'] = m[2]
      else
        let point['method'] = m[2]
      endif
    endif

    let m = matchlist(l, r_class_method)
    if !empty(m)
      let point = {}
      let point['class'] = m[1]
      " ruby does not allow numbers to be methods
      if m[2] =~ '^\d\+$'
        let point['line'] = m[2]
      else
        let point['method'] = m[2]
      endif
    endif

    call add(points, point)
  endfor

  " calculate markers:
  " we only show markers for file.line like breakpoints
  for p in points
    if has_key(p, 'file') && has_key(p, 'line')
      call add(signs, [bufnr(p.file), p.line, 'rdebug_breakpoint'])
    endif
  endfor

  call vim_addon_signs#Push("rdebug_breakpoint", signs )

  for ctx in values(s:c.ctxs)
    let c_ps = ctx.vim_managed_breakpoints

    if !has_key(ctx,'status')
      " for active processes update breakpoints

      " remove dropped breakpoints
      for i in range(len(c_ps)-1,0,-1)
        if !index(points, c_ps[i].point)
          call ctx.write('delete '. c_ps[i].nr ."\n")
          call remove(c_ps, i)
        endif
      endfor

      " add new breakpoints
      for b in points
        if 0 == len(filter(copy(c_ps),'v:val.point == b'))
          call add(c_ps, {'point': b, 'nr': ctx.next_breakpoint_nr})
          let ctx.next_breakpoint_nr += 1
          call ctx.write('break '. p.file .':'. p.line ."\n")
        endif
      endfor
    endif
  endfor
endf


fun! rdebug#ToggleLineBreakpoint()
  " yes, this implementation somehow sucks ..
  let file = expand('%')
  let line = getpos('.')[1]

  let old_win_nr = winnr()
  let old_buf_nr = bufnr('%')

  if !has_key(s:c,'var_break_buf_nr')
    call xdebug#BreakPointsBuffer()
    let restore = "bufnr"
  else
    let win_nr = bufwinnr(get(s:c, 'var_break_buf_nr', -1))

    if win_nr == -1
      let restore = 'bufnr'
      exec 'b '.s:c.var_break_buf_nr
    else
      let restore = 'active_window'
      exec win_nr.' wincmd w'
    endif

  endif

  " BreakPoint buffer should be active now.
  let pattern = escape(file,'\').':'.line
  let line = file.':'.line
  normal gg
  let found = search(pattern,'', s:auto_break_end)
  if found > 0
    " remove breakpoint
    exec found.'g/./d'
  else
    " add breakpoint
    call append(0, line)
  endif
  call rdebug#UpdateBreakPoints()
  if restore == 'bufnr'
    exec 'b '.old_buf_nr
  else
    exec old_win_nr.' wincmd w'
  endif
endf
