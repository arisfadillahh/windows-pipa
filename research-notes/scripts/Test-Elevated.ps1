$out = '<ARTIFACT_DIR>\elev-test.txt'
"started $(Get-Date -Format o)" | Set-Content -LiteralPath $out -Encoding UTF8
whoami /groups | Add-Content -LiteralPath $out

