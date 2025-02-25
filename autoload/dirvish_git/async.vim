" This file is an copy of https://github.com/airblade/vim-gitgutter/blob/719d4ec06a0fb0aa9f1dfaebcf4f9691e8dc3f73/autoload/gitgutter/async.vim
"
let s:available = has('nvim') || (
      \   has('job') && (
      \     (has('patch-7-4-1826') && !has('gui_running')) ||
      \     (has('patch-7-4-1850') &&  has('gui_running')) ||
      \     (has('patch-7-4-1832') &&  has('gui_macvim'))
      \   )
      \ )

let s:jobs = {}

function! dirvish_git#async#available()
  return s:available
endfunction


function! dirvish_git#async#execute(cmd, bufnr, handler) abort
  call dirvish_git#debug#log('[async] '.a:cmd)

  let options = {
        \   'stdoutbuffer': [],
        \   'buffer': a:bufnr,
        \   'handler': a:handler
        \ }
  let command = s:build_command(a:cmd)

  if has('nvim')
    call jobstart(command, extend(options, {
          \   'on_stdout': function('s:on_stdout_nvim'),
          \   'on_stderr': function('s:on_stderr_nvim'),
          \   'on_exit':   function('s:on_exit_nvim')
          \ }))
  else
    let job = job_start(command, {
          \   'out_cb':   function('s:on_stdout_vim', options),
          \   'err_cb':   function('s:on_stderr_vim', options),
          \   'close_cb': function('s:on_exit_vim', options)
          \ })
    let s:jobs[s:job_id(job)] = 1
  endif
endfunction


function! s:build_command(cmd)
  if has('unix')
    return ['sh', '-c', a:cmd]
  endif

  if has('win32')
    return has('nvim') ? ['cmd.exe', '/c', a:cmd] : 'cmd.exe /c '.a:cmd
  endif

  throw 'unknown os'
endfunction


function! s:on_stdout_nvim(_job_id, data, _event) dict abort
  if empty(self.stdoutbuffer)
    let self.stdoutbuffer = a:data
  else
    let self.stdoutbuffer = self.stdoutbuffer[:-2] +
          \ [self.stdoutbuffer[-1] . a:data[0]] +
          \ a:data[1:]
  endif
endfunction

function! s:on_stderr_nvim(_job_id, data, _event) dict abort
  if a:data != ['']  " With Neovim there is always [''] reported on stderr.
    call self.handler.err(self.buffer)
  endif
endfunction

function! s:on_exit_nvim(_job_id, exit_code, _event) dict abort
  if !a:exit_code
    call self.handler.out(self.buffer, join(self.stdoutbuffer, "\n"))
  endif
endfunction


function! s:on_stdout_vim(_channel, data) dict abort
  call add(self.stdoutbuffer, a:data)
endfunction

function! s:on_stderr_vim(channel, _data) dict abort
  call self.handler.err(self.buffer)
endfunction

function! s:on_exit_vim(channel) dict abort
  let job = ch_getjob(a:channel)
  let jobid = s:job_id(job)
  if has_key(s:jobs, jobid) | unlet s:jobs[jobid] | endif
  while 1
    if job_status(job) == 'dead'
      let exit_code = job_info(job).exitval
      break
    endif
    sleep 5m
  endwhile

  if !exit_code
    call self.handler.out(self.buffer, join(self.stdoutbuffer, "\n"))
  endif
endfunction

function! s:job_id(job)
  " Vim
  return job_info(a:job).process
endfunction
