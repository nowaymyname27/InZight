# InZight

InZight is an educational tool for visualizing how programs use memory.

The project is built to make memory behavior easier to understand by turning abstract concepts into a live, interactive view. Instead of reading static diagrams, learners can step through events and watch how memory changes over time.

## What InZight Is

InZight is a simulated process-memory visualizer written in Zig.

- It is intentionally educational-first, not an OS memory inspector.
- It uses a deterministic, illustrative memory model to teach concepts clearly.
- It is designed to help people build intuition for systems-level behavior.

## Why This Exists

The goal is simple: learning how a program uses memory should be easier.

A lot of people can read about stack and heap growth, but it is much harder to *see* the behavior in motion. InZight focuses on that gap by showing each memory event and how it changes overall process layout.

If learners can see memory movement, fragmentation, and segment boundaries directly, they can understand debugging and systems concepts faster and with more confidence.

## What It Visualizes

The simulator always presents the core process layout:

- Text Segment (Read/Execute, fixed)
- Data Segment (Read/Write, fixed)
- BSS Segment (Read/Write, fixed)
- Heap (Read/Write, grows upward)
- Unused Space / Gap
- Stack (Read/Write, grows downward)

The terminal UI includes:

- Segment table: address range, segment name, permissions, growth direction
- Symbol map of the address space (`T`, `D`, `B`, `.`, `0-F`, `G`, `S`)
- Event narration (`alloc`, `free`, `call`, `return`, failures)
- Heap and stack metrics (used/free bytes, fragmentation, stack usage)

## Controls

- `n` or `space`: advance one scripted step
- `a`: allocate on heap
- `f`: free oldest heap allocation
- `c`: simulate function call (push stack frame)
- `x`: simulate return (pop stack frame)
- `j` / `k` or arrow keys: scroll memory view
- `r`: reset simulation
- `q` or `Ctrl+C`: quit

## Build, Run, and Test

- Build: `zig build`
- Run: `zig build run`
- Run full tests: `zig build test`

## Run a Single Test

Use `zig test` with `--test-filter` for targeted checks:

- Root module test example:
  `zig test src/root.zig --test-filter "basic add functionality"`
- Simulator test example:
  `zig test src/sim.zig --test-filter "stack grows downward"`
- Compile tests without execution:
  `zig test src/sim.zig --test-no-exec`

## Teaching Notes

InZight currently favors conceptual clarity over runtime realism.

That is a deliberate choice: it helps learners focus on key ideas first, then move toward lower-level details later. The simulation model makes scenarios repeatable and easier to explain in classrooms, demos, and self-study.

## Roadmap (Educational Focus)

- Multiple abstraction levels (segment view, allocator internals, call-stack detail)
- Side-by-side strategy comparisons (first-fit, best-fit, worst-fit)
- Scripted lessons with guided explanations
- More examples around fragmentation and memory pressure
