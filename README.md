# vim-ansible-vault

Inline [Ansible Vault](https://docs.ansible.com/ansible/latest/vault_guide/index.html)
operations for YAML buffers in Vim, shelling out to the `ansible-vault` CLI.

Works on the inline `!vault` tag form:

```yaml
api_token: !vault |
  $ANSIBLE_VAULT;1.1;AES256
  31346531363834336431343635343834333637663430613435...
```

## Features

- **Encrypt** a plain `key: value` scalar in place (`:AnsibleVaultEncrypt`).
- **Decrypt** a `!vault` block in place (`:AnsibleVaultDecrypt`).
- **View one** vaulted value without changing the buffer, in a cursor popup
  (`:AnsibleVaultView`).
- **View all** vaulted values as inline virtual text after each header line,
  styled like a comment; toggle on/off (`:AnsibleVaultViewAll`,
  `:AnsibleVaultClear`).

## Requirements

- Vim 9.0+ (`:AnsibleVaultViewAll` needs `+textprop`).
- `ansible-vault` on `$PATH`.
- A vault password source (see below).

## Install

Any plugin manager, or drop the directory into your `runtimepath`.

vim-plug:

```vim
Plug 'sivel/vim-ansible-vault'
```

Then `:helptags` or let your manager generate them, and see
`:help ansible-vault`.

## Vault password

By default the plugin runs `ansible-vault` from the directory of the nearest
`ansible.cfg`, so a configured `vault_password_file` is used automatically. You
can also set one explicitly:

```vim
let g:ansible_vault_password_file = '~/.vault_pass'
" or
let g:ansible_vault_id = 'dev@~/.vault_dev'
```

## Configuration

| Variable | Default | Purpose |
| --- | --- | --- |
| `g:ansible_vault_executable` | `ansible-vault` | Binary to call |
| `g:ansible_vault_password_file` | unset | `--vault-password-file` |
| `g:ansible_vault_id` | unset | `--vault-id` |
| `g:ansible_vault_cwd` | nearest `ansible.cfg` dir | Where to run from |
| `g:ansible_vault_view_popup` | `1` | Popup vs command line for single view |
| `g:ansible_vault_view_highlight` | `Comment` | Inline preview highlight group |
| `g:ansible_vault_view_prefix` | `  # ` | Inline preview prefix |
| `g:ansible_vault_body_indent` | `2` | Ciphertext/body indent under the key |
| `g:ansible_vault_default_mappings` | `0` | Enable the mappings below |

## Mappings

None by default. Enable buffer-local mappings for yaml filetypes:

```vim
let g:ansible_vault_default_mappings = 1
```

| Mapping | Command |
| --- | --- |
| `<LocalLeader>ave` | `:AnsibleVaultEncrypt` |
| `<LocalLeader>avd` | `:AnsibleVaultDecrypt` |
| `<LocalLeader>avv` | `:AnsibleVaultView` |
| `<LocalLeader>ava` | `:AnsibleVaultViewAll` |
| `<LocalLeader>avc` | `:AnsibleVaultClear` |

Or map the commands yourself.

## License

MIT. See [LICENSE](LICENSE).
