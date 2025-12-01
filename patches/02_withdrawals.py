#!/usr/bin/env python3
"""
Patch: Withdrawals Support

Adds support for the 'withdrawals' column in the blocks dataset.
This serializes the withdrawals array as JSON string.
"""

from pathlib import Path

DESCRIPTION = "Add withdrawals column support to blocks dataset"

TARGET_FILE = Path("crates/freeze/src/datasets/blocks.rs")


def main():
    if not TARGET_FILE.exists():
        print(f"ERROR: {TARGET_FILE} not found")
        return False
    
    text = TARGET_FILE.read_text()
    
    # Check if already patched
    if 'withdrawals: Vec<Option<String>>,' in text and 'schema.has_column("withdrawals")' in text:
        print("Already patched")
        return "skipped"
    
    errors = []
    
    # Patch 1: Add withdrawals field to struct
    pattern1 = 'withdrawals_root: Vec<Option<Vec<u8>>>,'
    replacement1 = 'withdrawals_root: Vec<Option<Vec<u8>>>,\n    withdrawals: Vec<Option<String>>,'
    
    if 'withdrawals: Vec<Option<String>>,' not in text:
        if pattern1 in text:
            text = text.replace(pattern1, replacement1)
            print("  - Added withdrawals field to struct")
        else:
            errors.append("Could not find withdrawals_root field in struct")
    
    # Patch 2: Add serde_json import
    if 'use serde_json;' not in text:
        pattern2 = 'use polars::prelude::*;'
        replacement2 = 'use polars::prelude::*;\nuse serde_json;'
        
        if pattern2 in text:
            text = text.replace(pattern2, replacement2)
            print("  - Added serde_json import")
        else:
            errors.append("Could not find polars import for adding serde_json")
    
    # Patch 3: Add withdrawals processing logic
    pattern3 = 'store!(schema, columns, withdrawals_root, block.withdrawals_root.map(|x| x.0.to_vec()));'
    
    if 'schema.has_column("withdrawals")' not in text:
        if pattern3 in text:
            replacement3 = '''store!(schema, columns, withdrawals_root, block.withdrawals_root.map(|x| x.0.to_vec()));
    if schema.has_column("withdrawals") {
        let withdrawals_json = block.withdrawals.as_ref().map(|w| {
            serde_json::to_string(w).unwrap_or_else(|_| "[]".to_string())
        });
        columns.withdrawals.push(withdrawals_json);
    }'''
            text = text.replace(pattern3, replacement3)
            print("  - Added withdrawals processing logic")
        else:
            errors.append("Could not find withdrawals_root store! macro")
    
    if errors:
        for err in errors:
            print(f"  - ERROR: {err}")
        return False
    
    TARGET_FILE.write_text(text)
    return True


if __name__ == "__main__":
    import sys
    result = main()
    sys.exit(0 if result else 1)