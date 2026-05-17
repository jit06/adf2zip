# Amiga ADF to Zip Converter (for Emu68 Bootstrap)

A powerful Bash script designed to automate the extraction, reconstruction, and repackaging of Commodore Amiga applications and disk images (`.adf` or `.zip` containing ADFs) into clean, ready-to-use `.zip` archives. 

This tool is specifically optimized for prepping Amiga software for **Emu68-bootstrap** or modern Amiga emulators, handling complex real-world Amiga distribution quirks automatically.

---

## The Problem It Solves

Many classic Amiga applications distributed across multiple ADF floppy disks employ complex storage techniques to fit data onto 880KB (DD) or 1.76MB (HD) disks:
1. **Nested Compression:** Files inside the ADF disks are sometime compressed using the native Amiga `.lha` format.
2. **Split Files (Multi-part):** Large files or databases (like dictionaries, spelling guides, or large assets) are frequently split into multiple parts (`.part1`, `.part2`, etc.) across different floppy disks. On a real Amiga, the official installer merges these using the `join` tool.

Manually extracting the ADFs, unarchiving nested LHA files, tracking down fragmented multi-part files across directories, and reconstructing them is tedious. This script automates that entire pipeline in seconds on a modern Linux environment.

---

## Features

* **Multi-Source Ingestion:** Accepts local `.adf` files, local `.zip` files containing an ADF, or direct HTTP/HTTPS URLs (including robust support for Archive.org links).
* **Smart User-Agent Spoofing:** Automatically mimics a modern web browser to bypass WAF/protection blocks when downloading from online archives.
* **Recursive LHA Extraction:** Automatically detects and extracts nested `.lha` files inside the extracted disk structures into dedicated subdirectories using native `lha` tools.
* **Automated Amiga File Reassembly:** Detects split-part configurations (e.g., `gram.part1` in one disk folder and `gram.part2` in another), naturally sorts them, and merges them back into a single unified file (e.g., `gram`) in the primary folder—reproducing the Amiga `join` command perfectly while keeping original parts intact.
* **Safe Workspace & Absolute Paths:** Isolates all operations inside a secure `/tmp` sandbox, guaranteeing your final `.zip` files land safely in your specified output directory without cluttering your system.
* **Include some example:** Some of the best and well-known Amiga Software are prepared on the `lists` directory. Everything is downloaded from available sources. This github project does not host any Amiga software. 

---

## Prerequisites

These must be installed on your Linux host before running any script. 
| Tool | Purpose | Source / Project |
| :--- | :--- | :--- |
| **curl** | Downloading remote components and packages. | [Wget](https://www.gnu.org/software/wget/) / [Curl](https://curl.se/) |
| **lha** | Extracting Amiga `.lha` archives. | [GitHub](https://github.com/jca02266/lha) |
| **unadf** | Extracting files from Amiga Disk Files (`.adf`). | [unADF](http://lclevy.free.fr/adflib/) |
| **unzip** | Extracting firmware and tool archives. | [Info-ZIP](http://infozip.sourceforge.net/) |
| **zip** | creating `.zip` archive files for the final result | [Info-ZIP](http://infozip.sourceforge.net/) |
| **sed** | Path sanitization and configuration generation. | [GNU sed](https://www.gnu.org/software/sed/) |

## Installation

Simply clone this repository:
```bash
git clone --depth 1 https://github.com/jit06/adf2zip
```

## Usage

```bash
./adf2zip.sh [OPTIONS] <source1> [source2] ...
```

Options are:
* **-o, --output-dir <directory>:** Specify where to save the final ZIP files. Defaults to the current directory where the script is executed.
* **-h, --help:** Displays the help message

Example to build all archives ready to be installed with Emu68-bootstrap
```bash
./adf2zip.sh -o path/to/emu68-boostrap/custom lists/*
```

## How it works

```mermaid
graph TD
    A[Input: ADF or URL] --> B[Download & Extract ADF Structure]
    B --> C[Extract Nested .lha into dedicated subfolders]
    C --> D[Scan workspace for .part1, .part2...]
    D --> E[Chronologically 'cat' / Join parts]
    E --> F[Cache Flush & File Sync]
    F --> G[Pack into an optimized absolute .zip]
    G --> H[Clean up /tmp sandbox]
