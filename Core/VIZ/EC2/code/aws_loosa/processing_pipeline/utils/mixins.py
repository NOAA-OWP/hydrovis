# -*- coding: utf-8 -*-
"""
Created on Thu Jul 06 15:07:11 2017

@author: ArcGISServices
"""
import os
import shutil
import time


class FileHandlerMixin(object):
    """
    Mixin that provides helpful methods for working with files.

    Note: Child classes must provide a logger property named _log.
    """
    ERROR_FILE_EXISTS = 'Cannot create a file when that file already exists'
    ERROR_FILE_NOT_FOUND = 'The system cannot find the file specified'
    ERROR_FILE_IN_USE = 'The process cannot access the file because it is being used by another process'
    RETRIES = 2
    SLEEP_BETWEEN_RETRIES = 3  # seconds

    def _rename(self, src, dest, force=False):
        """
        More robust renaming method.

        Returns:
            bool: None if successfully renamed.
        """
        target_size = 0
        try:
            target_size = os.path.getsize(src)
            os.rename(src, dest)
        except OSError as exc:
            if self.ERROR_FILE_EXISTS in str(exc):
                if not force:
                    raise Exception(f'Unable to rename the file at {src} to {dest} because a file with that name already exists')
                else:
                    success = self._remove(dest, retries=0)
                    if success:
                        os.rename(src, dest)
                    else:
                        raise Exception(f'Unable to force rename the file at {src} to {dest} a file with that name already exists and could not be deleted.')

            elif self.ERROR_FILE_NOT_FOUND in str(exc):
                raise Exception(f'Unable to rename the following file because it does not exist: {src}')
            elif self.ERROR_FILE_IN_USE in str(exc):
                self._log.warning(f'Unable to rename {src}. An attempt will be made to copy it...')
                copy_success = self._copy(src, dest)
                if not copy_success:
                    raise Exception(f'Unable to copy the following file because it is being used by another process: {src}.')
            else:
                raise

        if target_size != os.path.getsize(dest):
            raise Exception("Filesizes did not match after renaming {} to {}".format(src, dest))

    def _remove(self, src, retries=3, sleep=3):
        """
        More robust removing method.

        Returns:
            bool: True if successfully renamed.
        """
        try:
            if os.path.isdir(src):
                for resource in os.listdir(src):
                    resource_path = os.path.join(src, resource)
                    if resource_path.endswith(".gdb"):
                        from arcpy.management import Delete
                        Delete(resource_path)
                    elif os.path.isdir(resource_path):
                        shutil.rmtree(resource_path)
                    else:
                        os.remove(resource_path)
                shutil.rmtree(src)
            elif os.path.isfile(src):
                os.remove(src)
        except OSError as exc:
            retry_count = 0
            success = False

            while retry_count < retries:
                self._log.warning(f'Unable to remove "{src}" due to following error:\n{exc}\nRetrying in {sleep} '
                                  'seconds...')
                time.sleep(sleep)
                try:
                    os.remove(src)
                    success = True
                    break
                except OSError:
                    pass
                retry_count += 1

            if not success:
                return False

        return True

    def _copy(self, src, dest):
        """
        Robust method of copying a src file to a dest.
        """
        try:
            shutil.copyfile(src, dest)
        except Exception as exc:
            self._log.warning('Error encountered while copying:')
            self._log.warning(str(exc))
            retries = 0
            success = False

            while retries < self.RETRIES:
                self._log.warning('Unable to copy "{0}". Retrying in 5 seconds...'.format(src))
                time.sleep(self.SLEEP_BETWEEN_RETRIES)
                try:
                    shutil.copyfile(src, dest)
                    success = True
                    break
                except Exception:
                    pass
                retries += 1
            if not success:
                return False

        return True

    def _copy_dir(self, src, dest, include_root=False):
        """
        Generic method used for recursively copying files in directory, ignoring errors.
        """
        if include_root:
            dest = os.path.join(dest, os.path.basename(src))
        if not os.path.exists(dest):
            os.makedirs(dest)

        for root, dirs, files in os.walk(src):
            for dir in dirs:
                src_dir = os.path.join(root, dir)
                dest_dir = src_dir.replace(src, dest)
                if not os.path.exists(dest_dir):
                    os.makedirs(dest_dir)

            for name in files:
                current_src = os.path.join(root, name)
                current_dest = current_src.replace(src, dest)
                try:
                    shutil.copy2(current_src, current_dest)
                except Exception as exc:
                    if not current_src.endswith('.lock'):
                        self._log.warning('Unable to copy file %s with error:\n%s' % (current_src, str(exc)))

    def _compare_dir(self, dir1, dir2):
        """
        Generic method used for recursively comparing files in directory.

        Returns:
            Bool. True if directories have same contents. False otherwise.
        """
        if not os.path.exists(dir1) or not os.path.exists(dir2):
            return False

        for root, dirs, files in os.walk(dir1):
            for name in files:
                # File in dir1 location path
                dir1_fpath = os.path.join(root, name)
                # File in dir2 location path
                dir2_fpath = dir1_fpath.replace(dir1, dir2)

                try:
                    files_match = os.path.getsize(dir1_fpath) == os.path.getsize(dir2_fpath)
                    if not files_match:
                        return False
                except Exception:
                    return False

        return True

    def _makedirs(self, directory):
        """
        Make the workspace directory if it doesn't exist.
        """
        try:
            os.makedirs(directory)
        except Exception:
            pass
