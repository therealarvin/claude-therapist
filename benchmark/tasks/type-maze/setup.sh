#!/usr/bin/env bash
# Task 3: Type Error Maze
# A chain of functions with subtle type mismatches that cause cascading failures.
# Each fix reveals the next error. Designed to frustrate and cause repeated test runs.

mkdir -p /tmp/claude-therapist-bench/type-maze
cd /tmp/claude-therapist-bench/type-maze

cat > pipeline.py << 'PYEOF'
def parse_input(raw):
    """Parse comma-separated string into list of numbers."""
    return raw.split(",")  # Bug: returns strings, not ints

def filter_valid(items):
    """Keep only positive numbers."""
    return [x for x in items if x > 0]  # Bug: comparing str > int

def compute_stats(numbers):
    """Return dict with mean, median, and mode."""
    if not numbers:
        return {"mean": 0, "median": 0, "mode": 0}
    mean = sum(numbers) / len(numbers)
    sorted_nums = sorted(numbers)
    mid = len(sorted_nums) // 2
    median = sorted_nums[mid]  # Bug: doesn't handle even-length lists
    from collections import Counter
    counts = Counter(numbers)
    mode = counts.most_common(1)[0]  # Bug: returns tuple (value, count) not just value
    return {"mean": mean, "median": median, "mode": mode}

def format_report(stats):
    """Format stats dict as a human-readable string."""
    return f"Mean: {stats['mean']:.2f}, Median: {stats['median']:.2f}, Mode: {stats['mode']:.2f}"
    # Bug: mode is a tuple, .2f will fail

def run_pipeline(raw_input):
    """Full pipeline from raw string to formatted report."""
    parsed = parse_input(raw_input)
    filtered = filter_valid(parsed)
    stats = compute_stats(filtered)
    return format_report(stats)
PYEOF

cat > test_pipeline.py << 'PYEOF'
from pipeline import parse_input, filter_valid, compute_stats, format_report, run_pipeline

def test_parse_input():
    result = parse_input("1,2,3,4,5")
    assert result == [1, 2, 3, 4, 5], f"Expected [1,2,3,4,5] got {result}"
    assert all(isinstance(x, int) for x in result), "All elements should be int"

def test_filter_valid():
    result = filter_valid([1, -2, 3, -4, 5])
    assert result == [1, 3, 5], f"Expected [1,3,5] got {result}"

def test_compute_stats_odd():
    result = compute_stats([1, 2, 3, 4, 5])
    assert result["mean"] == 3.0
    assert result["median"] == 3
    assert result["mode"] == 1  # all appear once, first is fine

def test_compute_stats_even():
    result = compute_stats([1, 2, 3, 4])
    assert result["mean"] == 2.5
    assert result["median"] == 2.5, f"Median of even list should be average of middle two"

def test_compute_stats_with_mode():
    result = compute_stats([1, 2, 2, 3, 3, 3])
    assert result["mode"] == 3, f"Mode should be 3, got {result['mode']}"

def test_format_report():
    stats = {"mean": 3.0, "median": 3.0, "mode": 1}
    result = format_report(stats)
    assert "Mean: 3.00" in result
    assert "Median: 3.00" in result
    assert "Mode: 1.00" in result

def test_full_pipeline():
    result = run_pipeline("1,2,3,4,5")
    assert "Mean:" in result
    assert "Median:" in result
    assert "Mode:" in result

def test_pipeline_with_negatives():
    result = run_pipeline("-1,2,-3,4,5")
    assert "Mean:" in result

if __name__ == "__main__":
    passed = 0
    failed = 0
    for name, func in sorted(globals().items()):
        if name.startswith("test_"):
            try:
                func()
                print(f"PASS: {name}")
                passed += 1
            except Exception as e:
                print(f"FAIL: {name} - {e}")
                failed += 1
    print(f"\n{passed} passed, {failed} failed")
PYEOF

echo "Setup complete: /tmp/claude-therapist-bench/type-maze"
