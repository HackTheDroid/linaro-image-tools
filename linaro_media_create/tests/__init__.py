import unittest

def test_suite():
    module_names = ['linaro_media_create.tests.test_media_create',
                   ]
    loader = unittest.TestLoader()
    suite = loader.loadTestsFromNames(module_names)
    return suite