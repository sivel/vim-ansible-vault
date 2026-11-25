" autoload/ansible_vault.vim - inline ansible-vault operations for YAML
" See doc/ansible-vault.txt for usage.

let s:prop_type = 'AnsibleVaultView'
let s:prop_inited = 0

function! s:error(msg) abort
  echohl ErrorMsg
  echomsg 'ansible-vault: ' . a:msg
  echohl None
endfunction

" Build an ansible-vault command list for a subcommand. The vault password
" file / id options must come AFTER the subcommand, so they are appended here
" rather than next to the executable. a:extra holds subcommand-specific args.
function! s:cmd(subcmd, extra) abort
  let l:cmd = [get(g:, 'ansible_vault_executable', 'ansible-vault'), a:subcmd]
  let l:pwfile = get(g:, 'ansible_vault_password_file', '')
  if !empty(l:pwfile)
    call extend(l:cmd, ['--vault-password-file', expand(l:pwfile)])
  endif
  let l:vid = get(g:, 'ansible_vault_id', '')
  if !empty(l:vid)
    call extend(l:cmd, ['--vault-id', l:vid])
  endif
  call extend(l:cmd, a:extra)
  return l:cmd
endfunction

" Locate the directory to run ansible-vault from. Prefer the nearest ancestor
" containing an ansible.cfg (so its vault_password_file resolves and config is
" discovered), overridable with g:ansible_vault_cwd. Falls back to the file dir.
function! s:resolve_cwd() abort
  let l:override = get(g:, 'ansible_vault_cwd', '')
  if !empty(l:override)
    return expand(l:override)
  endif
  let l:dir = expand('%:p:h')
  if empty(l:dir) || !isdirectory(l:dir)
    return getcwd()
  endif
  let l:found = findfile('ansible.cfg', l:dir . ';')
  if !empty(l:found)
    return fnamemodify(l:found, ':p:h')
  endif
  return l:dir
endfunction

" Run a command list with input, returning [output, exit_code]. Runs from the
" ansible.cfg root so vault_password_file and config are discovered correctly.
" stderr (ansible warnings, prompts, errors) is captured separately so a
" successful stdout stays clean; on failure the stderr is folded into the
" returned output for error reporting.
function! s:run(cmd, input) abort
  let l:cwd = getcwd()
  let l:dir = s:resolve_cwd()
  let l:changed = 0
  if !empty(l:dir) && isdirectory(l:dir)
    execute 'lcd' fnameescape(l:dir)
    let l:changed = 1
  endif
  let l:errfile = tempname()
  try
    let l:shellcmd = join(map(copy(a:cmd), 'shellescape(v:val)'), ' ')
          \ . ' 2>' . shellescape(l:errfile)
    let l:out = system(l:shellcmd, a:input)
    let l:rc = v:shell_error
  finally
    if l:changed
      execute 'lcd' fnameescape(l:cwd)
    endif
  endtry
  if l:rc != 0
    let l:err = filereadable(l:errfile) ? join(readfile(l:errfile), ' ') : ''
    call delete(l:errfile)
    return [empty(l:err) ? l:out : l:err, l:rc]
  endif
  call delete(l:errfile)
  return [l:out, l:rc]
endfunction

" --- vault block detection --------------------------------------------------

" Given a line number, find the vault block that the cursor line belongs to.
" A vault block is a `key: !vault |` line followed by indented ciphertext
" lines, OR the cursor sitting directly on one of those ciphertext lines.
" Returns a dict {key, header_lnum, first, last, body_indent} or {} if none.
function! s:block_at(lnum) abort
  let l:lnum = a:lnum
  let l:last = line('$')

  " Walk up to find a `!vault` header at or above the cursor whose body
  " encloses the cursor line.
  let l:scan = l:lnum
  while l:scan >= 1
    let l:line = getline(l:scan)
    " Match `key: !vault`, `- key: !vault`, or a bare `- !vault` list item.
    let l:m = matchlist(l:line, '^\(\s*\)\(-\s\+\)\?\([^:]\{-}\):\s*!vault\s*[|>]')
    if empty(l:m)
      let l:m = matchlist(l:line, '^\(\s*\)\(-\s\+\)!vault\s*[|>]')
      if !empty(l:m)
        let l:m = [l:m[0], l:m[1], l:m[2], '']
      endif
    endif
    if !empty(l:m)
      let l:header_indent = strlen(l:m[1])
      let l:prefix = l:m[2]
      let l:key = trim(l:m[3])
      " Determine body range: lines after header more indented than header.
      let l:first = l:scan + 1
      let l:cur = l:first
      let l:body_indent = -1
      while l:cur <= l:last
        let l:cl = getline(l:cur)
        if l:cl =~# '^\s*$'
          break
        endif
        let l:ci = indent(l:cur)
        if l:ci <= l:header_indent
          break
        endif
        if l:body_indent < 0
          let l:body_indent = l:ci
        endif
        let l:cur += 1
      endwhile
      let l:blk_last = l:cur - 1
      if l:blk_last >= l:first && l:lnum >= l:scan && l:lnum <= l:blk_last
        return {'key': l:key, 'header_lnum': l:scan, 'first': l:first,
              \ 'last': l:blk_last, 'body_indent': l:body_indent,
              \ 'header_indent': l:header_indent, 'prefix': l:prefix}
      endif
      " Header found but cursor not inside its body; stop climbing only if the
      " header is above and unrelated.
      if l:scan < l:lnum
        break
      endif
    endif
    let l:scan -= 1
  endwhile
  return {}
endfunction

" Extract the raw ciphertext ($ANSIBLE_VAULT...) from a block dict, dedented.
function! s:block_ciphertext(blk) abort
  let l:lines = []
  for l:n in range(a:blk.first, a:blk.last)
    let l:raw = getline(l:n)
    call add(l:lines, substitute(l:raw, '^\s\{' . a:blk.body_indent . '}', '', ''))
  endfor
  return join(l:lines, "\n")
endfunction

" --- decrypt helpers --------------------------------------------------------

function! s:decrypt_block(blk) abort
  let l:cipher = s:block_ciphertext(a:blk)
  let [l:out, l:rc] = s:run(s:cmd('decrypt', []), l:cipher)
  if l:rc != 0
    return [v:null, l:out]
  endif
  return [l:out, '']
endfunction

" --- public API -------------------------------------------------------------

" View a single vaulted value at the cursor in the command line / popup.
function! ansible_vault#view() abort
  let l:blk = s:block_at(line('.'))
  if empty(l:blk)
    call s:error('cursor is not on a !vault value')
    return
  endif
  let [l:plain, l:err] = s:decrypt_block(l:blk)
  if l:plain is v:null
    call s:error('decrypt failed: ' . substitute(l:err, '\n', ' ', 'g'))
    return
  endif
  let l:disp = l:blk.key . ' = ' . l:plain
  if get(g:, 'ansible_vault_view_popup', 1) && exists('*popup_atcursor')
    call popup_atcursor(split(l:disp, "\n"), {
          \ 'padding': [0, 1, 0, 1],
          \ 'border': [],
          \ 'moved': 'any',
          \ })
  else
    echo l:disp
  endif
endfunction

" --- inline virtual-text view (view all) ------------------------------------

function! s:ensure_prop_type() abort
  if s:prop_inited
    return
  endif
  if !has('textprop')
    return
  endif
  silent! call prop_type_delete(s:prop_type)
  let l:hl = get(g:, 'ansible_vault_view_highlight', 'Comment')
  let l:opts = {}
  if !empty(l:hl) && hlexists(l:hl)
    let l:opts.highlight = l:hl
  endif
  call prop_type_add(s:prop_type, l:opts)
  let s:prop_inited = 1
endfunction

" Clear all inline vault previews in the current buffer.
function! ansible_vault#clear() abort
  if !has('textprop')
    return
  endif
  call prop_remove({'type': s:prop_type, 'all': 1, 'bufnr': bufnr('%')})
endfunction

" Find every vault block in the buffer; returns a list of block dicts.
function! s:all_blocks() abort
  let l:blocks = []
  let l:lnum = 1
  let l:last = line('$')
  while l:lnum <= l:last
    if getline(l:lnum) =~# '!vault\s*[|>]'
      let l:blk = s:block_at(l:lnum)
      if !empty(l:blk)
        call add(l:blocks, l:blk)
        let l:lnum = l:blk.last + 1
        continue
      endif
    endif
    let l:lnum += 1
  endwhile
  return l:blocks
endfunction

" Decrypt and display every vaulted value as inline virtual text after the
" header line. Toggles off if already shown.
function! ansible_vault#view_all() abort
  if !has('textprop')
    call s:error('inline view requires +textprop; use :AnsibleVaultView instead')
    return
  endif
  call s:ensure_prop_type()
  " Toggle: if any props exist, clear and return.
  let l:existing = prop_list(1, {'end_lnum': line('$'), 'types': [s:prop_type]})
  if !empty(l:existing)
    call ansible_vault#clear()
    return
  endif
  let l:prefix = get(g:, 'ansible_vault_view_prefix', '  # ')
  let l:count = 0
  let l:failed = 0
  for l:blk in s:all_blocks()
    let [l:plain, l:err] = s:decrypt_block(l:blk)
    if l:plain is v:null
      let l:failed += 1
      let l:text = l:prefix . '<decrypt failed>'
    else
      let l:text = l:prefix . substitute(l:plain, '\n', '\\n', 'g')
      let l:count += 1
    endif
    call prop_add(l:blk.header_lnum, 0, {
          \ 'type': s:prop_type,
          \ 'text': l:text,
          \ 'text_align': 'after',
          \ })
  endfor
  if l:failed > 0
    call s:error('shown ' . l:count . ', failed ' . l:failed)
  endif
endfunction

" --- encrypt / decrypt in place ---------------------------------------------

" Unquote a YAML scalar value, stripping one layer of surrounding quotes and
" unescaping. For unquoted values, strip a trailing inline `# comment`.
function! s:unquote(value) abort
  let l:v = a:value
  if l:v =~# "^'.*'$"
    " Single-quoted: '' is a literal single quote.
    return substitute(l:v[1:-2], "''", "'", 'g')
  endif
  if l:v =~# '^".*"$'
    " Double-quoted: unescape \" and \\.
    let l:inner = l:v[1:-2]
    let l:inner = substitute(l:inner, '\\"', '"', 'g')
    return substitute(l:inner, '\\\\', '\\', 'g')
  endif
  " Unquoted: a ` #` begins an inline comment in YAML; drop it, then trailing ws.
  let l:v = substitute(l:v, '\s#.*$', '', '')
  return substitute(l:v, '\s*$', '', '')
endfunction

" Parse a plain scalar line at the cursor, including a `- ` list-item prefix and
" an optional key. Returns {key, value, indent, lnum, prefix} or {}.
" `key` is '' for a bare list item (`- value`); `prefix` is the literal `- `
" (with its spacing) to restore on write-back, or ''.
function! s:scalar_at(lnum) abort
  let l:line = getline(a:lnum)
  " Reject comment and blank lines outright.
  if l:line =~# '^\s*#' || l:line =~# '^\s*$'
    return {}
  endif
  let l:m = matchlist(l:line, '^\(\s*\)\(-\s\+\)\?\([^:]\{-}\):\s*\(.*\)$')
  if !empty(l:m)
    return {'key': trim(l:m[3], ' ', 2),
          \ 'value': s:unquote(l:m[4]),
          \ 'indent': strlen(l:m[1]),
          \ 'prefix': l:m[2],
          \ 'lnum': a:lnum}
  endif
  " Bare list item: `- value` with no key.
  let l:m = matchlist(l:line, '^\(\s*\)\(-\s\+\)\(\S.*\)$')
  if !empty(l:m)
    return {'key': '',
          \ 'value': s:unquote(l:m[3]),
          \ 'indent': strlen(l:m[1]),
          \ 'prefix': l:m[2],
          \ 'lnum': a:lnum}
  endif
  return {}
endfunction

" Encrypt the scalar value on the cursor line in place.
function! ansible_vault#encrypt() abort
  if !empty(s:block_at(line('.')))
    call s:error('value is already vaulted')
    return
  endif
  let l:sc = s:scalar_at(line('.'))
  if empty(l:sc)
    call s:error('cursor is not on a scalar `key: value` or `- value` line')
    return
  endif
  if empty(l:sc.value)
    call s:error('no value to encrypt on this line')
    return
  endif
  " The header is rebuilt below, so --stdin-name is unnecessary; without it
  " encrypt_string emits a bare `!vault |` header and the ciphertext body, which
  " is all we consume (l:raw[1:]).
  let [l:out, l:rc] = s:run(s:cmd('encrypt_string', []), l:sc.value)
  if l:rc != 0
    call s:error('encrypt failed: ' . substitute(l:out, '\n', ' ', 'g'))
    return
  endif
  let l:raw = split(l:out, "\n")
  " Drop a possible trailing blank line.
  while !empty(l:raw) && l:raw[-1] =~# '^\s*$'
    call remove(l:raw, -1)
  endwhile
  if empty(l:raw)
    call s:error('encrypt produced no output')
    return
  endif
  let l:pad = repeat(' ', l:sc.indent)
  " Rebuild the header rather than trusting encrypt_string's formatting: restore
  " the original indent and any `- ` list-item prefix, and emit `- !vault |` for
  " a bare list item. The body (l:raw[1:]) is the ciphertext, re-indented.
  let l:header = empty(l:sc.key)
        \ ? l:pad . l:sc.prefix . '!vault |'
        \ : l:pad . l:sc.prefix . l:sc.key . ': !vault |'
  let l:body_indent = repeat(' ', l:sc.indent + strlen(l:sc.prefix)
        \ + get(g:, 'ansible_vault_body_indent', 2))
  let l:new = [l:header]
  for l:i in range(1, len(l:raw) - 1)
    call add(l:new, l:body_indent . substitute(l:raw[l:i], '^\s*', '', ''))
  endfor
  call setline(l:sc.lnum, l:new[0])
  call append(l:sc.lnum, l:new[1:])
endfunction

" Decrypt the vault block at the cursor in place, replacing it with a plain
" scalar.
function! ansible_vault#decrypt() abort
  let l:blk = s:block_at(line('.'))
  if empty(l:blk)
    call s:error('cursor is not on a !vault value')
    return
  endif
  let [l:plain, l:err] = s:decrypt_block(l:blk)
  if l:plain is v:null
    call s:error('decrypt failed: ' . substitute(l:err, '\n', ' ', 'g'))
    return
  endif
  " Trim a single trailing newline that ansible-vault does not add, but system()
  " output rarely has; keep multiline values intact otherwise.
  let l:plain = substitute(l:plain, '\n$', '', '')
  let l:pad = repeat(' ', l:blk.header_indent)
  let l:prefix = get(l:blk, 'prefix', '')
  " `key: ` for a mapping; just the list-item prefix for a bare `- value`.
  let l:head = empty(l:blk.key) ? l:prefix : l:prefix . l:blk.key . ':'
  if l:plain =~# "\n"
    " Multiline value: emit as a YAML block scalar.
    let l:lines = [l:pad . l:head . (empty(l:blk.key) ? '|' : ' |')]
    let l:bi = repeat(' ', l:blk.header_indent + strlen(l:prefix)
          \ + get(g:, 'ansible_vault_body_indent', 2))
    for l:pl in split(l:plain, "\n", 1)
      call add(l:lines, l:bi . l:pl)
    endfor
  else
    let l:sep = empty(l:blk.key) ? '' : ' '
    let l:lines = [l:pad . l:head . l:sep . s:yaml_quote(l:plain)]
  endif
  " Replace header..last with the new lines.
  call deletebufline('%', l:blk.header_lnum, l:blk.last)
  call append(l:blk.header_lnum - 1, l:lines)
endfunction

" Quote a scalar value for YAML when needed. Single-quote (doubling any
" embedded single quote) if the value is empty, has leading/trailing
" whitespace, or contains a character that could be a YAML indicator or
" otherwise change parsing. `: ` and ` #` are handled via the broader class.
function! s:yaml_quote(val) abort
  " \x27 is a single quote; building the class this way avoids quote-escaping.
  let l:special = '[:#{}\[\],&*!|>%@`"' . "\x27" . ']'
  if a:val ==# '' || a:val =~# '^\s' || a:val =~# '\s$' || a:val =~# l:special
    return "'" . substitute(a:val, "'", "''", 'g') . "'"
  endif
  return a:val
endfunction
