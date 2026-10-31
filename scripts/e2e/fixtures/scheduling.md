# Scheduling, in brief

A fixture for the Loci CLI smoke test, written for it.

## Filtering

The scheduler first drops the nodes a pod cannot run on: not enough free CPU
or memory, a taint the pod does not tolerate, a node selector that does not
match.

## Scoring

The nodes that remain are ranked, and the pod is bound to the best one.
