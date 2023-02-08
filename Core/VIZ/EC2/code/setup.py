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
    install_requires=[
        'isodate == 0.6.0',
        'jinja2 == 2.10',
        'python-dateutil == 2.7.3',
        'python-logstash-async == 1.4.1',
        'pyyaml == 5.1',
        'voluptuous == 0.11.5',
        'six == 1.12.0',
        'psycopg2 == 2.9.1',
        'sqlalchemy == 1.4.23',
        'boto3 == 1.18.43',
        'botocore == 1.13.50',
        'jmespath == 0.10.0',
        'filelock == 3.0.12',
        'requests == 2.19.1',
        'numpy == 1.15.1',
        'netCDF4 == 1.4.1',
        'flake8 >= 3.7',
        'coverage == 4.5',
        'xarray == 0.14.1',
        'natsort == 7.0.1',
        'elasticsearch == 7.5.1',
        'XlsxWriter == 1.3.3'
    ]
)
