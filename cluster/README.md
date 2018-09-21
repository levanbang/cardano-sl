# Cluster

## Getting Started

This module provides an executable for starting a demo cluster of nodes.
It is designed to remove all the overhead of setting up a configuration
and an environment and to _just work_, out-of-the-box. Minor configuration
adjustments are however possible via environment variables. 

```
stack exec cardano-sl-cluster:demo
```

This spawns four core nodes, one relay node and one wallet node
running respectively on:

| NodeId | Address        | API Address    | API Doc Address |
| ---    | ---            | ---            | ---             |
| core0  | localhost:3000 | \-             | \-              |
| core1  | localhost:3001 | \-             | \-              |
| core2  | localhost:3002 | \-             | \-              |
| core3  | localhost:3003 | \-             | \-              |
| core4  | localhost:3004 | \-             | \-              |
| relay  | localhost:3005 | \-             | \-              |
| wallet | \-             | localhost:8090 | localhost:8190  |



## Configuring Nodes

Almost _anything_ from the normal CLI arguments of a node or a wallet node can be
configured via an ENV variable using an `UPPER_SNAKE_CASE` naming, correctly
prefixed with `DEMO_` with a few gotchas:

- Flags need an explicit boolean value

- There's no ENV vars mapping to (i.e. you can't configure):
    - `--topology`
    - `--tlscert`
    - `--tlsca`
    - `--tlskey`
    - `--logger-config`
    - `--node-id`
    - `--db-path`
    - `--wallet-db-path`

- There's an extra `LOG_SEVERITY` variable that can be set to `Debug`, `Info` 
  and so forth to ajust logging severity for _all_ nodes.

- When it make senses, variable values are automatically incremented by the
  node index. For instance, if you provide `LISTEN=127.0.0.1:3000`, then 
    - core0 will receive "127.0.0.1:3000"
    - core1 will receive "127.0.0.1:3001"
    - core2 will receive "127.0.0.1:3002"
    - etc.

  This is the case for:
    - `--listen`
    - `--wallet-address`
    - `--wallet-doc-address`

For instance, one can disable TLS client authentication doing:

```
DEMO_NO_CLIENT_AUTH=True stack test cardano-sl-wallet-new:demo
```


### Relative FilePath

One can provide relative filepath as values for ENV vars. They are computed from 
the `wallet-new` folder, so for instance, providing `./state-demo` will point 
to the directory `$(git rev-parse --show-toplevel)/wallet-new/state-demo`.


### State Directory

By default, each node receives a temporary state directory from the system;
probably somewhere in `/tmp`. This location can always be overriden by 
providing an extra `DEMO_STATE_DIR` variable with a custom location.

Note that, each default has been choosen in such way that they won't conflict
if all nodes were to share the same state directory :)
