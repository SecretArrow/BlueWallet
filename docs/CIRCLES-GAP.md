# Circles bridge: endpoint coverage in the app build

`circles.js` is the largest embedded page (2268 lines) and the only one that
speaks a *bridge* protocol rather than a wallet protocol. This file records,
per release, how much of that protocol the **app's local server** actually
serves — because the page is reachable from the wallet header and a 404 there
looks like a bug rather than a missing feature.

Measured by `sdk/test/embed.test.mjs` (`circles bridge endpoint coverage`),
which recomputes this from the sources on every CI run.

| Release | Endpoints used by `circles.js` | Served by app local server | Missing |
|---|---|---|---|
| v0.18.x (Fase C3) | 75 | 7 | 68 |

## What the app build does serve

Only the read/browse path plus asset upload:

| Endpoint | Use |
|---|---|
| `/api/wallet` | address + `rpc_url` for `circle.info` |
| `/api/balance` | wallet balances (migrated to the adapter in C3) |
| `/api/circle/info` | circle metadata (`renderMeta`) |
| `/api/circle/asset` | asset fetch |
| `/api/circle/asset_ciphertext` | sealed asset ciphertext |
| `/api/circle/asset_ciphertext_by_key` | key-scoped ciphertext |
| `/api/circle/deploy` | deploy a circle |
| `/api/circle/asset_encrypted` | upload an encrypted asset |
| `/api/fhe/encrypt`, `/api/fhe/decrypt` | FHE helpers |

## What is missing

Every endpoint below is served by the desktop `webcli` server (`main.cpp`) and
**not** by the app. Groups:

- **FHE** — `circle/fhe/{commit,deserialize_cipher,encrypt,decrypt,load_pk,pedersen,serialize_cipher,verify_bound,verify_zero}`
- **Circle compute** — `circle/compute`
- **Object store** — `circle/object_{bind,detail,list,member,member_attach,member_detach,members,policy_define,refs,summary,transition_apply}`
- **Outbox / relay** — `circle/outbox_{claim,intent,open,status}`, `circle/relay_{cancel,claim}`, `relay/{health,ingress,receipt,request,response,status}`
- **Key policy** — `circle/key_{erase,extend,grant,policy,policy_put,revoke}`
- **Policies & state** — `circle/{balance_binding,balance_cell,balance_cell_put,balance_workflow,hfhe_policy,hfhe_policy_put,ingress_commit,ingress_packet,register_binding,register_cell,register_cell_put,register_workflow,sealed_slot_put,slot_policy,slot_policy_put,state_descriptor,state_descriptor_put,state_policy,transport_policy,transport_policy_put}`
- **Program / keys / send** — `program/{call,info,storage,view}`, `keys`, `send`
- **Assets** — `circle/asset_plain`, `circle/asset_ciphertext_by_slot`, `circle/asset_ciphertext_by_state`

## Why this is documented rather than implemented

Each missing route needs a real backend decision (which RPC, which auth
level, whether it needs the wallet unlocked). Implementing 68 routes "to make
a page work" would be guesswork; the strangler approach is to make the
boundary explicit and keep the desktop server authoritative until each group
is designed. `circles.js` therefore probes `/api/relay/health` on load and
tells the user which build they are on, instead of failing opaquely across 68
calls.

## Full missing list

<!-- generated: sdk/test/embed.test.mjs keeps this in sync -->
- `/api/circle/asset_ciphertext_by_slot`
- `/api/circle/asset_ciphertext_by_state`
- `/api/circle/asset_plain`
- `/api/circle/balance_binding`
- `/api/circle/balance_cell`
- `/api/circle/balance_cell_put`
- `/api/circle/balance_workflow`
- `/api/circle/compute`
- `/api/circle/fhe/commit`
- `/api/circle/fhe/decrypt`
- `/api/circle/fhe/deserialize_cipher`
- `/api/circle/fhe/encrypt`
- `/api/circle/fhe/load_pk`
- `/api/circle/fhe/pedersen`
- `/api/circle/fhe/serialize_cipher`
- `/api/circle/fhe/verify_bound`
- `/api/circle/fhe/verify_zero`
- `/api/circle/hfhe_policy`
- `/api/circle/hfhe_policy_put`
- `/api/circle/ingress_commit`
- `/api/circle/ingress_packet`
- `/api/circle/key_erase`
- `/api/circle/key_extend`
- `/api/circle/key_grant`
- `/api/circle/key_policy`
- `/api/circle/key_policy_put`
- `/api/circle/key_revoke`
- `/api/circle/object_bind`
- `/api/circle/object_detail`
- `/api/circle/object_list`
- `/api/circle/object_member`
- `/api/circle/object_member_attach`
- `/api/circle/object_member_detach`
- `/api/circle/object_members`
- `/api/circle/object_policy_define`
- `/api/circle/object_refs`
- `/api/circle/object_summary`
- `/api/circle/object_transition_apply`
- `/api/circle/outbox_claim`
- `/api/circle/outbox_intent`
- `/api/circle/outbox_open`
- `/api/circle/outbox_status`
- `/api/circle/register_binding`
- `/api/circle/register_cell`
- `/api/circle/register_cell_put`
- `/api/circle/register_workflow`
- `/api/circle/relay_cancel`
- `/api/circle/relay_claim`
- `/api/circle/sealed_slot_put`
- `/api/circle/slot_policy`
- `/api/circle/slot_policy_put`
- `/api/circle/state_descriptor`
- `/api/circle/state_descriptor_put`
- `/api/circle/state_policy`
- `/api/circle/transport_policy`
- `/api/circle/transport_policy_put`
- `/api/keys`
- `/api/program/call`
- `/api/program/info`
- `/api/program/storage`
- `/api/program/view`
- `/api/relay/health`
- `/api/relay/ingress`
- `/api/relay/receipt`
- `/api/relay/request`
- `/api/relay/response`
- `/api/relay/status`
- `/api/send`
