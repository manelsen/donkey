#!/usr/bin/env python3
"""
Extract skeletons from Rust files - keeps signatures only, removes bodies.
"""

import os
import re
from pathlib import Path
from typing import List, Tuple

# Patterns to match different Rust constructs
PAT_MOD_DECL = re.compile(r"^(\s*)pub\s*\(\s*crate\s*\)\s*mod\s+(\w+)", re.MULTILINE)
PAT_PUB_MOD = re.compile(r"^(\s*)pub\s+mod\s+(\w+)", re.MULTILINE)
PAT_MOD = re.compile(r"^(\s*)mod\s+(\w+)", re.MULTILINE)

PAT_PUB_FN = re.compile(r"^(\s*)pub\s+(?:async\s+)?fn\s+(\w+)\s*\(", re.MULTILINE)
PAT_FN = re.compile(r"^(\s*)(?:async\s+)?fn\s+(\w+)\s*\(", re.MULTILINE)

PAT_PUB_STRUCT = re.compile(
    r"^(\s*)pub\s+(?:struct|enum|union|type)\s+(\w+)", re.MULTILINE
)
PAT_STRUCT = re.compile(r"^(\s*)(?:struct|enum|union|type)\s+(\w+)", re.MULTILINE)

PAT_PUB_TRAIT = re.compile(r"^(\s*)pub\s+trait\s+(\w+)", re.MULTILINE)
PAT_TRAIT = re.compile(r"^(\s*)trait\s+(\w+)", re.MULTILINE)

PAT_IMPL = re.compile(
    r"^(\s*)impl\s+(?:<[^>]*>\s+)?(\w+)\s*(?:<[^>]*>)?\s*(?:for\s+(\w+)\s*(?:<[^>]*>)?)?",
    re.MULTILINE,
)

PAT_USE = re.compile(r"^\s*use\s+.*?;", re.MULTILINE)
PAT_EXTERN_CRATE = re.compile(r"^\s*extern\s+crate\s+\w+;", re.MULTILINE)

PAT_ATTR = re.compile(r"^\s*#\[.*?\]\s*", re.MULTILINE)

PAT_DOC_COMMENT = re.compile(r"^\s*///[^\n]*\n", re.MULTILINE)
PAT_DOC_COMMENT_BLOCK = re.compile(r"^\s*/\*\*.*?\*/\s*\n", re.MULTILINE.DOTALL)
PAT_COMMENT = re.compile(r"^\s*//.*\n", re.MULTILINE)
PAT_COMMENT_BLOCK = re.compile(r"^\s*/\*[^*].*?\*/\s*\n", re.MULTILINE.DOTALL)


def extract_skeleton(content: str) -> str:
    """
    Extract skeleton from Rust source code.
    Keeps signatures, imports, module declarations, comments.
    Removes function bodies, impl bodies, struct field defaults.
    """
    lines = content.split("\n")
    result = []
    i = 0
    brace_depth = 0
    in_fn = False
    in_struct = False
    in_impl = False
    in_enum = False
    fn_start_line = 0
    impl_start_line = 0

    while i < len(lines):
        line = lines[i]
        stripped = line.strip()

        # Skip empty lines but preserve spacing
        if not stripped:
            result.append(line)
            i += 1
            continue

        # Preserve comments, docstrings, and attributes
        if (
            stripped.startswith("///")
            or stripped.startswith("//!")
            or stripped.startswith("/*")
            or stripped.startswith("#[")
        ):
            result.append(line)
            i += 1
            continue

        # Preserve use statements
        if stripped.startswith("use ") or stripped.startswith("extern crate "):
            result.append(line)
            i += 1
            continue

        # Preserve mod declarations (not definitions)
        if stripped.startswith("mod ") and not stripped.endswith(";"):
            # This is a module definition, skip the whole block
            result.append(line)
            i += 1
            # Find the opening brace
            while i < len(lines) and "{" not in lines[i]:
                i += 1
            if i < len(lines):
                i += 1
                brace_depth = 1
                while i < len(lines) and brace_depth > 0:
                    if "{" in lines[i]:
                        brace_depth += lines[i].count("{")
                    if "}" in lines[i]:
                        brace_depth -= lines[i].count("}")
                    i += 1
            continue

        # Handle fn declarations
        if re.search(r"(?<!\w)(?:async\s+)?fn\s+\w+\s*\(", line):
            in_fn = True
            fn_start_line = len(result)

            # Check if it's a one-liner or has a body
            if "{" in line:
                # Extract signature up to opening brace
                brace_idx = line.index("{")
                sig = line[:brace_idx].rstrip() + " {"
                result.append(sig)
                brace_depth = 1
                i += 1

                # Skip to matching closing brace
                while i < len(lines) and brace_depth > 0:
                    if "{" in lines[i]:
                        brace_depth += lines[i].count("{")
                    if "}" in lines[i]:
                        brace_depth -= lines[i].count("}")
                    i += 1

                # Add ellipsis for body
                result.append("    ...")
                result.append("}")
            else:
                # No opening brace on this line, might be multi-line signature
                result.append(line)
                i += 1

                # Continue until we find the opening brace
                while i < len(lines) and "{" not in lines[i]:
                    result.append(lines[i])
                    i += 1

                if i < len(lines):
                    # Found the opening brace
                    brace_idx = lines[i].index("{")
                    if brace_idx > 0:
                        sig_line = lines[i][:brace_idx].rstrip() + " {"
                        result.append(sig_line)
                    brace_depth = 1
                    i += 1

                    # Skip to matching closing brace
                    while i < len(lines) and brace_depth > 0:
                        if "{" in lines[i]:
                            brace_depth += lines[i].count("{")
                        if "}" in lines[i]:
                            brace_depth -= lines[i].count("}")
                        i += 1

                    # Add ellipsis for body
                    result.append("    ...")
                    result.append("}")

            in_fn = False
            continue

        # Handle struct/enum/union/type declarations
        if re.search(r"(?<!\w)(?:struct|enum|union|type)\s+\w+", line):
            if "{" in line:
                # Struct with fields
                brace_idx = line.index("{")
                sig = line[:brace_idx].rstrip() + " {"
                result.append(sig)
                brace_depth = 1
                i += 1

                # Skip to matching closing brace
                while i < len(lines) and brace_depth > 0:
                    if "{" in lines[i]:
                        brace_depth += lines[i].count("{")
                    if "}" in lines[i]:
                        brace_depth -= lines[i].count("}")
                    i += 1

                result.append("    ...")
                result.append("}")
            else:
                # Struct without body or with = (type alias)
                result.append(line)
                i += 1
            continue

        # Handle impl blocks
        if re.search(r"(?<!\w)impl\s+", line):
            # This is the start of an impl block
            result.append(line)
            i += 1

            # Find the opening brace
            while i < len(lines) and "{" not in lines[i]:
                result.append(lines[i])
                i += 1

            if i < len(lines):
                brace_idx = lines[i].index("{")
                if brace_idx > 0:
                    result.append(lines[i][:brace_idx].rstrip() + " {")
                else:
                    result.append(lines[i])
                brace_depth = 1
                i += 1

                # Process impl body - keep item signatures
                impl_lines = []
                in_impl_fn = False
                impl_fn_start = 0

                while i < len(lines) and brace_depth > 0:
                    impl_line = lines[i]
                    impl_stripped = impl_line.strip()

                    # Skip comments and attributes
                    if (
                        impl_stripped.startswith("///")
                        or impl_stripped.startswith("//!")
                        or impl_stripped.startswith("/*")
                        or impl_stripped.startswith("#[")
                    ):
                        impl_lines.append(impl_line)
                        i += 1
                        continue

                    # Check for fn in impl
                    if re.search(r"(?<!\w)(?:async\s+)?fn\s+\w+\s*\(", impl_line):
                        in_impl_fn = True
                        impl_fn_start = len(impl_lines)

                        if "{" in impl_line:
                            # One-liner or inline
                            brace_idx = impl_line.index("{")
                            sig = impl_line[:brace_idx].rstrip() + " {"
                            impl_lines.append(sig)
                            local_depth = 1
                            i += 1

                            while (
                                i < len(lines)
                                and local_depth > 0
                                and brace_depth + local_depth - 1 > 0
                            ):
                                if "{" in lines[i]:
                                    local_depth += lines[i].count("{")
                                    brace_depth += lines[i].count("{")
                                if "}" in lines[i]:
                                    local_depth -= lines[i].count("}")
                                    brace_depth -= lines[i].count("}")
                                i += 1

                            impl_lines.append("    ...")
                            impl_lines.append("}")
                            in_impl_fn = False
                        else:
                            impl_lines.append(impl_line)
                            i += 1
                            while i < len(lines) and "{" not in lines[i]:
                                impl_lines.append(lines[i])
                                i += 1

                            if i < len(lines):
                                brace_idx = lines[i].index("{")
                                if brace_idx > 0:
                                    impl_lines.append(
                                        lines[i][:brace_idx].rstrip() + " {"
                                    )
                                local_depth = 1
                                i += 1

                                while (
                                    i < len(lines)
                                    and local_depth > 0
                                    and brace_depth + local_depth - 1 > 0
                                ):
                                    if "{" in lines[i]:
                                        local_depth += lines[i].count("{")
                                        brace_depth += lines[i].count("{")
                                    if "}" in lines[i]:
                                        local_depth -= lines[i].count("}")
                                        brace_depth -= lines[i].count("}")
                                    i += 1

                                impl_lines.append("    ...")
                                impl_lines.append("}")
                                in_impl_fn = False
                        continue

                    # Track braces in impl body
                    if "{" in impl_line:
                        brace_depth += impl_line.count("{")
                    if "}" in impl_line:
                        brace_depth -= impl_line.count("}")

                    i += 1

                # Add all processed impl lines
                result.extend(impl_lines)

            continue

        # Handle standalone closing braces
        if stripped == "}":
            if not in_fn and not in_impl:
                result.append(line)
            i += 1
            continue

        # Preserve other content (attributes, etc.)
        result.append(line)
        i += 1

    return "\n".join(result)


def process_file(src_path: Path, dst_path: Path) -> None:
    """Process a single Rust file and write its skeleton."""
    with open(src_path, "r", encoding="utf-8") as f:
        content = f.read()

    skeleton = extract_skeleton(content)

    # Ensure destination directory exists
    dst_path.parent.mkdir(parents=True, exist_ok=True)

    with open(dst_path, "w", encoding="utf-8") as f:
        f.write(skeleton)


def main():
    source_dir = Path("/home/micelio/git/donkey/inspiration/moltis")
    output_dir = Path("/home/micelio/git/donkey/docs/blueprint/moltis")

    # Find all .rs files
    rs_files = list(source_dir.rglob("*.rs"))

    processed = 0
    skipped = 0

    for rs_file in rs_files:
        # Compute relative path from source dir
        rel_path = rs_file.relative_to(source_dir)

        # Skip target directories and build artifacts
        if "target" in rel_path.parts or "examples" in rel_path.parts:
            skipped += 1
            continue

        # Create output path with _skel suffix
        dst_file = output_dir / rel_path.with_name(
            rel_path.stem + "_skel" + rel_path.suffix
        )

        process_file(rs_file, dst_file)
        processed += 1
        print(f"Processed: {rel_path}")

    print(f"\nSummary:")
    print(f"  Processed: {processed} files")
    print(f"  Skipped: {skipped} files")
    print(f"  Output: {output_dir}")


if __name__ == "__main__":
    main()
