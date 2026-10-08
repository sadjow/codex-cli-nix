import pathlib
import unittest

import yaml

ROOT = pathlib.Path(__file__).resolve().parents[1]


class ReleaseWorkflowsTest(unittest.TestCase):
    def test_tags_use_the_commit_that_passed_the_build(self):
        workflow = yaml.safe_load((ROOT / '.github/workflows/create-version-tag.yml').read_text())
        checkout = next(step for step in workflow['jobs']['create-tag']['steps']
                        if step.get('uses', '').startswith('actions/checkout@'))
        self.assertEqual(checkout['with'].get('ref'), '${{ github.event.workflow_run.head_sha }}',
                         'A newer default-branch commit must not be tagged using an older build result')

    def test_chained_build_tests_its_event_commit(self):
        workflow = yaml.safe_load((ROOT / '.github/workflows/build.yml').read_text())
        checkout = next(step for step in workflow['jobs']['build']['steps']
                        if step.get('uses', '').startswith('actions/checkout@'))
        self.assertEqual(checkout.get('with', {}).get('ref'), '${{ github.sha }}',
                         'A chained build must not silently switch to a newer default-branch commit')


if __name__ == '__main__':
    unittest.main()
