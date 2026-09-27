# Development

```sh
# Run specs:
direnv exec . bin/specs
# which is just a helper that calls: crystal spec --verbose --error-trace
# Run specs with a different crystal version (uses asdf)
ASDF_CRYSTAL_VERSION=1.14.0 direnv exec . bin/specs

# Lint:
direnv exec . bin/lint

# Format:
direnv exec . bin/format

# Integration tests:
direnv exec . scripts/integration
direnv exec . crystal run examples/basic.cr
direnv exec . crystal run examples/capture.cr
```

To build the precompiler: `direnv exec . shards build`. The `hamlc` target in
`shard.yml` supports `--help`, `--check`, and generated method wrappers.
`--check` validates Haml structure; native Crystal compilation is still needed
to check expressions and types. Tooling can explicitly require `haml/compiler`
and call `Haml.compile` to obtain Crystal source.
