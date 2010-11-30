from contextlib import contextmanager
import os
import subprocess
import sys

from testtools import TestCase

from hwpack.testing import TestCaseWithFixtures

from media_create.boot_cmd import create_boot_cmd
from media_create import ensure_command

from media_create.remove_binary_dir import remove_binary_dir
from media_create.unpack_binary_tarball import unpack_binary_tarball

from media_create.tests.fixtures import (
    CreateTempDirFixture,
    CreateTarballFixture,
    )


class TestEnsureCommand(TestCase):

    apt_get_called = False

    def test_command_already_present(self):
        with self.mock_apt_get_install():
            ensure_command.ensure_command('apt-get', 'apt')
        self.assertFalse(self.apt_get_called)

    def test_command_not_present(self):
        with self.mock_apt_get_install():
            ensure_command.ensure_command('apt-get-two-o', 'apt-2')
        self.assertTrue(self.apt_get_called)

    @contextmanager
    def mock_apt_get_install(self):
        def mock_apt_get_install(cmd, pkg):
            self.apt_get_called = True
        orig_func = ensure_command.apt_get_install
        ensure_command.apt_get_install = mock_apt_get_install
        yield
        ensure_command.apt_get_install = orig_func


class TestCreateBootCMD(TestCase):

    expected_boot_cmd = (
        "setenv bootcmd 'fatload mmc mmc_option kernel_addr uImage; "
        "fatload mmc mmc_option initrd_addr uInitrd; bootm kernel_addr "
        "initrd_addr'\nsetenv bootargs 'serial_opts splash_opts  "
        "root=UUID=root_uuid boot_args'\nboot")

    def test_create_boot_cmd(self):
        cmd = create_boot_cmd(
            is_live=False, is_lowmem=False, mmc_option='mmc_option',
            root_uuid='root_uuid', kernel_addr="kernel_addr",
            initrd_addr="initrd_addr", serial_opts="serial_opts",
            boot_args_options="boot_args", splash_opts="splash_opts")
        self.assertEqual(self.expected_boot_cmd, cmd)

    def test_create_boot_cmd_as_script(self):
        args = "%s -m media_create.boot_cmd " % sys.executable
        args += ("0 0 mmc_option root_uuid kernel_addr initrd_addr "
                 "serial_opts boot_args splash_opts")
        process = subprocess.Popen(
            args, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        stdout, stderr = process.communicate()
        self.assertEqual(self.expected_boot_cmd, stdout)


class TestRemoveBinaryDir(TestCaseWithFixtures):

    def setUp(self):
        super(TestRemoveBinaryDir, self).setUp()
        self.temp_dir_fixture = CreateTempDirFixture()
        self.useFixture(self.temp_dir_fixture)
    
    def test_remove_binary_dir(self):
        rc = remove_binary_dir(
            binary_dir=self.temp_dir_fixture.get_temp_dir(),
            as_root=False)
        self.assertEqual(rc, 0)
        self.assertFalse(os.path.exists(
            self.temp_dir_fixture.get_temp_dir()))


class TestUnpackBinaryTarball(TestCaseWithFixtures):

    def setUp(self):
        super(TestUnpackBinaryTarball, self).setUp()
        
        self.temp_dir_fixture = CreateTempDirFixture()
        self.useFixture(self.temp_dir_fixture)
        
        self.tarball_fixture = CreateTarballFixture(
            self.temp_dir_fixture.get_temp_dir())
        self.useFixture(self.tarball_fixture)
    
    def test_unpack_binary_tarball(self):
        rc = unpack_binary_tarball(self.tarball_fixture.get_tarball(),
            as_root=False)
        self.assertEqual(rc, 0)