# Normalizer comparison

This development-only tool rebuilds the controlled complex-structure PDF and
runs three extraction candidates:

- the production Docling adapter;
- the production Xberg fast adapter, including its quality gates;
- an experimental Xberg layout profile.

Run it from anywhere in the repository:

```console
dev/normalizer-comparison/run
```

By default, a new result directory is created under
`_build/normalizer-comparison/`. It contains the generated PDF, tool versions,
raw normalizer output, standard output and error, exit codes, elapsed times,
`summary.json`, and a concise `report.md`. Candidate quality-gate failures are
recorded and do not prevent the other candidates from running. The command
returns a failure after writing the report if any candidate produced no
document, so an incomplete comparison cannot pass unnoticed.

Use a fresh explicit destination when retaining a named comparison:

```console
dev/normalizer-comparison/run \
  --output-directory _build/normalizer-comparison/xberg-1.1.0
```

The runner refuses to overwrite an existing result directory. The expected
signals are versioned in
[`test/fixtures/complex-structure.expected.json`](../../test/fixtures/complex-structure.expected.json).
They measure heading presence and order, column markers, table cells and rows,
and leaked page furniture. These signals make release-to-release regressions
visible but do not constitute a universal benchmark or an automatic default
selection policy.

The directory has no Dune install stanza and is not part of the Sandwalk
runtime package. It additionally requires `xelatex`, `xberg`, Docling's
`sandwalk-docling-normalize`, `jq`, `mq`, and Python 3 on the development
machine.
