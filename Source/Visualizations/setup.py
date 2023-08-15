from setuptools import setup, find_packages

VERSION = '1.0.0'

setup(
    name='aws_loosa',
    version=VERSION,
    description='National Water Model Post Processing and Analysis Tools for AWS',
    license='',
    author='Corey Krewson, Tyler Schrag',
    author_email='corey.krewson@noaa.gov',
    url='http://water.noaa.gov',
    packages=find_packages(),
    test_suite="aws_loosa.tests",
    install_requires=[]
)
