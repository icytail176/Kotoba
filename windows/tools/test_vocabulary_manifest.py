"""Deterministic validation/drift tests; no network or user data."""
import contextlib
import csv
import io
import json
import shutil
import tempfile
import unittest
from pathlib import Path
import vocabulary_manifest as tool

class ManifestToolsTests(unittest.TestCase):
    def setUp(self):
        self.directory=tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.repo=Path(self.directory.name)
        self.manifest=json.loads((tool.ROOT/tool.TARGET).read_text(encoding='utf-8'))
        files=list(self.manifest['generatedFrom']['sourceSha256'])+[tool.TARGET.as_posix(),tool.LEDGER.as_posix(),'shared/vocabulary/canonical_vocabulary.schema.json']
        for relative in files:
            dest=self.repo/relative;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(tool.ROOT/relative,dest)
    def validate(self, manifest=None):
        with contextlib.redirect_stdout(io.StringIO()):
            return tool.validate(self.repo,manifest)
    def csv_rows(self):
        path=self.repo/'Kotoba/Resources/eggrolls_kotoba_N5_strict.csv'
        return path,tool.read_csv(path,tool.HEADERS)
    def write_csv(self,path,rows):
        with path.open('w',encoding='utf-8',newline='') as stream:
            writer=csv.DictWriter(stream,fieldnames=tool.HEADERS);writer.writeheader();writer.writerows(rows)
    def test_deterministic_pristine_bootstrap_replay(self):
        # No established identity file is ever overwritten; replay only in disposable temp repo.
        (self.repo/tool.TARGET).unlink();(self.repo/tool.LEDGER).unlink()
        with contextlib.redirect_stdout(io.StringIO()):tool.bootstrap(self.repo)
        self.assertEqual(json.loads((self.repo/tool.TARGET).read_text(encoding='utf-8')),self.manifest)
    def test_frozen_snapshot_valid_and_real_metadata_coverage(self):
        m=self.validate();self.assertEqual(m['entryCount'],10609)
        audit=tool.duplicate_audit(m['entries']);self.assertEqual(audit['loanwordCoverage'],836)
        self.assertEqual(audit['loanwordLanguages']['chi'],2);self.assertEqual(audit['pitchTagCoverage'],10398)
        self.assertEqual(audit['expressionReading']['crossBookGroups'],10)
    def test_bootstrap_never_overwrites_established_identity(self):
        before=(self.repo/tool.TARGET).read_bytes()
        with self.assertRaisesRegex(ValueError,'bootstrap refused'):tool.bootstrap(self.repo)
        self.assertEqual(before,(self.repo/tool.TARGET).read_bytes())
    def test_upstream_reorder_does_not_change_identity_or_drift(self):
        path,rows=self.csv_rows();rows.reverse();self.write_csv(path,rows)
        validated=self.validate();self.assertEqual(validated['entries'][0]['canonicalId'],self.manifest['entries'][0]['canonicalId'])
    def test_metadata_drift_is_reported_as_changed(self):
        path,rows=self.csv_rows();rows[0]['meaningChinese']+=' changed';self.write_csv(path,rows)
        with self.assertRaisesRegex(ValueError,'SOURCE DRIFT.*changed'):self.validate()
    def test_lexical_rename_reports_added_removed_and_never_rematches(self):
        path,rows=self.csv_rows();rows[0]['expression']+='X';self.write_csv(path,rows)
        with self.assertRaisesRegex(ValueError,'SOURCE DRIFT.*added.*removed'):self.validate()
    def test_source_count_growth_reports_added_instead_of_regenerating(self):
        path,rows=self.csv_rows();added=dict(rows[0],expression='new fixture',reading='new reading');rows.append(added);self.write_csv(path,rows)
        with self.assertRaisesRegex(ValueError,'SOURCE DRIFT.*added'):self.validate()
    def test_identity_and_required_field_failures_are_rejected(self):
        m=json.loads(json.dumps(self.manifest));m['entries'][0]['canonicalId']=m['entries'][1]['canonicalId']
        with self.assertRaises(ValueError):self.validate(m)
        m=json.loads(json.dumps(self.manifest));m['entries'][0]['bookKey']='unknown'
        with self.assertRaisesRegex(ValueError,'unknown book'):self.validate(m)
        m=json.loads(json.dumps(self.manifest));del m['entries'][0]['expression']
        with self.assertRaisesRegex(ValueError,'missing required'):self.validate(m)
    def test_identity_ledger_anchor_mismatch_rejected(self):
        m=json.loads(json.dumps(self.manifest));m['entries'][0]['identityAnchor']='0'*64
        with self.assertRaisesRegex(ValueError,'identity reservation'):self.validate(m)

if __name__=='__main__':unittest.main()
