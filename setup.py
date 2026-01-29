# Licensed under the MIT License
# https://github.com/grongierisc/iris_pex_embedded_python/blob/main/LICENSE

import os
from typing import List

from setuptools import setup

def package_files(directory: str) -> List[str]:
    paths = []
    for (path, directories, filenames) in os.walk(directory):
        for filename in filenames:
            paths.append(os.path.join('.', path, filename))
    return paths

extra_files = package_files('src/grongier/iris')

def main():
    # Read the readme for use as the long description
    with open(os.path.join(os.path.abspath(os.path.dirname(__file__)),
                            'README.md'), encoding='utf-8') as readme_file:
        long_description = readme_file.read()

    # Do the setup
    setup(
        name='iris_fhir_interactions',
        description='iris_fhir_interactions',
        long_description=long_description,
        long_description_content_type='text/markdown',
        version='0.0.1',
        author='grongier',
        author_email='guillaume.rongier@intersystems.com',
        keywords='iris_fhir_interactions',
        url='https://github.com/grongierisc/iris-fhir-python-strategy',
        license='MIT',
        classifiers=[
            'Development Status :: 5 - Production/Stable',
            'Intended Audience :: Developers',
            'License :: OSI Approved :: MIT License',
            'Operating System :: OS Independent',
            'Programming Language :: Python :: 3.6',
            'Programming Language :: Python :: 3.7',
            'Programming Language :: Python :: 3.8',
            'Programming Language :: Python :: 3.9',
            'Programming Language :: Python :: 3.10',
            'Programming Language :: Python :: 3.11',
            'Topic :: Utilities'
        ],
        package_dir={'': 'src/python'},
        packages=['FhirInteraction'],
        python_requires='>=3.6',

    )


if __name__ == '__main__':
    main()
