#!/usr/bin/env python3
"""
Patch: Null-safe trace functions

Some RPCs return `null` instead of `[]` for empty trace lists, causing
deserialization errors. This patch catches those errors and returns empty Vecs.

Functions patched:
- trace_replay_block_transactions
- trace_block
"""

import re
from pathlib import Path

DESCRIPTION = "Make trace functions null-safe (handle RPCs returning null instead of [])"

TARGET_FILE = Path("crates/freeze/src/types/sources.rs")


def main():
    if not TARGET_FILE.exists():
        print(f"ERROR: {TARGET_FILE} not found")
        return False
    
    text = TARGET_FILE.read_text()
    
    # Check if already patched
    if "Handle null responses from some RPCs" in text:
        print("Already patched")
        return "skipped"
    
    modified = False
    
    # Patch 1: trace_replay_block_transactions
    pattern1 = re.compile(
        r'(    pub async fn trace_replay_block_transactions\(\n'
        r'        &self,\n'
        r'        block: BlockNumber,\n'
        r'        trace_types: Vec<TraceType>,\n'
        r'    \) -> Result<Vec<BlockTrace>> \{\n'
        r'        let _permit = self\.permit_request\(\)\.await;\n)'
        r'        Self::map_err\(\n'
        r'            source_provider!\(self, trace_replay_block_transactions\(block, trace_types\)\)\.await,\n'
        r'        \)\n'
        r'(    \})',
        re.MULTILINE
    )
    
    replacement1 = r'''\1        let res = Self::map_err(
            source_provider!(self, trace_replay_block_transactions(block, trace_types)).await,
        );
        // Handle null responses from some RPCs (they return null instead of [])
        match res {
            Ok(traces) => Ok(traces),
            Err(CollectError::ProviderError(ref e))
                if e.to_string().contains("null")
                    || e.to_string().contains("invalid type") =>
            {
                Ok(Vec::new())
            }
            Err(err) => Err(err),
        }
\2'''
    
    if pattern1.search(text):
        text = pattern1.sub(replacement1, text)
        print("  - Patched trace_replay_block_transactions")
        modified = True
    else:
        print("  - WARNING: Could not find trace_replay_block_transactions pattern")
    
    # Patch 2: trace_block (single-line map_err)
    pattern2 = re.compile(
        r'(    pub async fn trace_block\(&self, block_num: BlockNumber\) -> Result<Vec<Trace>> \{\n'
        r'        let _permit = self\.permit_request\(\)\.await;\n)'
        r'        Self::map_err\(source_provider!\(self, trace_block\(block_num\)\)\.await\)\n'
        r'(    \})',
        re.MULTILINE
    )
    
    replacement2 = r'''\1        let res = Self::map_err(source_provider!(self, trace_block(block_num)).await);
        // Handle null responses from some RPCs (they return null instead of [])
        match res {
            Ok(traces) => Ok(traces),
            Err(CollectError::ProviderError(ref e))
                if e.to_string().contains("null")
                    || e.to_string().contains("invalid type") =>
            {
                Ok(Vec::new())
            }
            Err(err) => Err(err),
        }
\2'''
    
    if pattern2.search(text):
        text = pattern2.sub(replacement2, text)
        print("  - Patched trace_block")
        modified = True
    else:
        print("  - WARNING: Could not find trace_block pattern")
    
    if modified:
        TARGET_FILE.write_text(text)
        return True
    
    return False


if __name__ == "__main__":
    import sys
    result = main()
    sys.exit(0 if result else 1)