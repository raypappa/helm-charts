# Repository guidance

- This repository currently contains one application chart, `charts/lldap`; its templates and defaults live in `charts/lldap/templates/` and `charts/lldap/values.yaml`.
- Treat that `values.yaml` and the templates as authoritative: `charts/lldap/README.md` has stale values and install paths.
- The chart has fixed resource/secret references and reads `.Values.namespace`, which is not defined in `values.yaml`. When changing names, namespace, or secret settings, inspect rendered output (for example, `helm template lldap charts/lldap`).
- A normal chart PR must bump `version` in `Chart.yaml` and add a non-empty `annotations."artifacthub.io/changes"` list; Renovate PRs are exempt from the changelog requirement. CI validates the chart version and changelog entries.

## Commands

- `task` lists available tasks.
- `task chart:lint CHART=lldap` runs chart-testing lint on this chart; requires `ct` installed.
- `task chart:integration-test CHART=lldap` runs `ct install` and requires a reachable Kubernetes cluster (CI provisions k3d).
- `task chart:unit-test CHART=lldap` installs the `helm-unittest` plugin, updates chart dependencies, then runs `tests/**/*_test.yaml`; no chart test files currently exist.
- `task lint` runs chart-testing lint in Docker for changed charts; use `task lint-all` to lint all charts.
- `task precommit:run-all` runs the configured pre-commit hooks across all files.
- To build docs: `pip install -r docs/requirements.txt`, then `mkdocs build -f .ci/mkdocs/mkdocs.yml`.
