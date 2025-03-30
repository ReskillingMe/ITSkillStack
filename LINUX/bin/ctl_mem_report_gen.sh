#!/bin/bash
# Control-M Memory Report Generator
INPUT_DIR="$1"
[ -z "$INPUT_DIR" ] && { echo "Usage: $0 <data_directory>"; exit 1; }

OUTPUT_HTML="$INPUT_DIR/analysis_report.html"

# Generate HTML header
cat > "$OUTPUT_HTML" <<EOF
<html>
<head>
<title>Control-M Memory Analysis Report</title>
<style>
table { border-collapse: collapse; width: 100%; }
th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
tr:nth-child(even) { background-color: #f2f2f2; }
</style>
</head>
<body>
<h1>Control-M Memory Analysis Report</h1>
<p>Generated on: $(date)</p>
EOF

# Add process hierarchy section
echo "<h2>1. Process Hierarchy</h2>" >> "$OUTPUT_HTML"
echo "<pre>" >> "$OUTPUT_HTML"
cat "$INPUT_DIR/process_tree.txt" >> "$OUTPUT_HTML"
echo "</pre>" >> "$OUTPUT_HTML"

# Add memory groups section
echo "<h2>2. Memory Group Analysis</h2>" >> "$OUTPUT_HTML"
for group in 0-10MB 10-50MB 50-100MB 100MB+; do
    if [ -f "$INPUT_DIR/${group}.txt" ]; then
        echo "<h3>${group} Group</h3>" >> "$OUTPUT_HTML"
        echo "<table><tr><th>PID</th><th>PPID</th><th>User</th><th>%MEM</th><th>RSS</th><th>Command</th></tr>" >> "$OUTPUT_HTML"
        awk '{print "<tr><td>"$1"</td><td>"$2"</td><td>"$3"</td><td>"$4"</td><td>"$5"</td><td>"$7"</td></tr>"}' "$INPUT_DIR/${group}.txt" >> "$OUTPUT_HTML"
        echo "</table>" >> "$OUTPUT_HTML"
    fi
done

# Close HTML
cat >> "$OUTPUT_HTML" <<EOF
</body>
</html>
EOF

echo "HTML report generated: $OUTPUT_HTML"

