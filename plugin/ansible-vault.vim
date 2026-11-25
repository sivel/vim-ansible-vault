" plugin/ansible-vault.vim - commands and mappings for inline ansible-vault ops
" Maintainer: sivel
" Load guard
if exists('g:loaded_ansible_vault')
  finish
endif
let g:loaded_ansible_vault = 1

if v:version < 900
  echohl WarningMsg
  echomsg 'vim-ansible-vault requires Vim 9.0+'
  echohl None
  finish
endif

command! -bar AnsibleVaultEncrypt call ansible_vault#encrypt()
command! -bar AnsibleVaultDecrypt call ansible_vault#decrypt()
command! -bar AnsibleVaultView    call ansible_vault#view()
command! -bar AnsibleVaultViewAll call ansible_vault#view_all()
command! -bar AnsibleVaultClear   call ansible_vault#clear()

" Optional default mappings, enabled with g:ansible_vault_default_mappings = 1.
function! s:buffer_maps() abort
  nnoremap <buffer> <silent> <LocalLeader>ave :AnsibleVaultEncrypt<CR>
  nnoremap <buffer> <silent> <LocalLeader>avd :AnsibleVaultDecrypt<CR>
  nnoremap <buffer> <silent> <LocalLeader>avv :AnsibleVaultView<CR>
  nnoremap <buffer> <silent> <LocalLeader>ava :AnsibleVaultViewAll<CR>
  nnoremap <buffer> <silent> <LocalLeader>avc :AnsibleVaultClear<CR>
endfunction

" Set up the default mappings: install on matching buffers from now on, and
" also on the current buffer if it already matches (covers enabling the plugin
" after the yaml buffer was opened).
function! s:enable_default_mappings() abort
  augroup ansible_vault_maps
    autocmd!
    autocmd FileType yaml,yaml.ansible,ansible call s:buffer_maps()
  augroup END
  if index(['yaml', 'yaml.ansible', 'ansible'], &filetype) >= 0
    call s:buffer_maps()
  endif
endfunction

if get(g:, 'ansible_vault_default_mappings', 0)
  call s:enable_default_mappings()
endif
