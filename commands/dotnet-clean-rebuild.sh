#!/usr/bin/env bash
set -euo pipefail
cd ..
dotnet clean
dotnet restore
dotnet build
