# Public-release sanitization

Only the clean release copy was modified.

The original frozen research artifacts remain unchanged.

Transformations applied for public portability:

- Broad24 absolute trace paths were replaced by trace filenames; workload identities and SHA256 values were preserved.
- E32/128 absolute raw-log paths were replaced by relative raw_logs/ filenames; scientific numeric fields were preserved.
- Yosys scripts were converted from machine-specific absolute paths to repository-relative input/output paths.
- Public README wording was generalized to avoid naming unrelated private research workspaces.

workloads_24.tsv original SHA256: c5d758521875e6ea35a31ffac2fbeff952a4fd4a78ef346652629293b9e39ac2
workloads_24.tsv public SHA256:   fe844103b241d069951f7f70cef342768d13f4aa76e4efe39bb4f7c70ca225cb

E32_128_RECORDS.tsv original SHA256: b1f50693e28518af6baf820763257e609f7c2f2e5cdfcc74f55057451405cb77
E32_128_RECORDS.tsv public SHA256:   5353cf1e1281f2bd1a9a309ad42fa64d0c2f91d74dc5d1dde80a9e9ff8ed8a7f

generic.ys original SHA256: b15debdfdb17d0fafe7d2b38bf99f92b925eaeac546feae96712cd2ffcc12b21
generic.ys public SHA256:   20866a477440d302d8405445a6e2edbf612bbbfdabf2d32511196ef9773ba911

synth_ecp5.ys original SHA256: 6d33fef9104d90fb523ab3387d426f669605c24ca0413f49690626bd5a8909e6
synth_ecp5.ys public SHA256:   224c15151905a3e61939cd046be00328e1d60ffd93c6e6c083edbf3908612461

## Config whitespace sanitization

- Public `oogway_dev.ini` copies had one trailing ASCII space removed from affected lines.
- Configuration keys and values were not changed.
- Original frozen research artifacts remain unchanged.
- Original SHA256: `dd1b89accc3576d70ffb037e002d0c8e8fd58d55482bb9ca087fe5227213f0bc`
- Public sanitized SHA256: `74ec162670120d6fbca5fc52d28e37b18251ef9a178c69f2e49651d8e1ae2c1b`

## TSV structural whitespace

- `results/fixed_cap/ARM_SUMMARY.tsv` and `results/transfer/T4_ALL25_RESULTS.tsv` retain trailing tab characters where frozen rows contain empty trailing fields.
- These tabs are part of the TSV column structure and were intentionally not stripped.
- `.gitattributes` disables Git whitespace warnings only for these two result tables.
- Scientific table bytes were not modified for this Git policy change.
