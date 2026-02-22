import re
with open('Cargo.toml', 'r') as f:
    s = f.read()

lines = s.split('\n')
out_lines = []
in_bin = False
for line in lines:
    stripped = line.strip()
    if stripped.startswith('[[bin]]'):
        in_bin = True
        continue
    if in_bin and stripped.startswith('[') and not stripped.startswith('[[bin]]'):
        in_bin = False
    if not in_bin:
        out_lines.append(line)
s = '\n'.join(out_lines)

print("keyboard_test_client" in s)
