## A simple command line that help to install cls class into an iris namespace.

import os
from importlib.resources import files
import argparse

path = str(files('iris_fhir_python_strategy').joinpath('cls'))

def main():
    ## simple pass argument to install cls into iris namespace
    # arg is --namespace or -n for short
    parser = argparse.ArgumentParser(description='Install cls class into iris namespace.')
    parser.add_argument('--namespace', '-n', type=str, required=False, help='The namespace to install cls class into.')
    parser.add_argument('--endpoint', '-e', help='Publish Patient merge definition and refresh metadata for an existing Python-strategy endpoint.')
    args = parser.parse_args()

    namespace = args.namespace

    if namespace:
        os.environ['IRISNAMESPACE'] = namespace

    import iris
    status = iris.cls('%SYSTEM.OBJ').LoadDir(path, 'cubk', "*.cls", 1)
    if iris.cls('%SYSTEM.Status').IsError(status):
        raise RuntimeError(iris.cls('%SYSTEM.Status').GetErrorText(status))
    if args.endpoint:
        assets = str(files('iris_fhir_python_strategy').joinpath('fhir'))
        iris.cls('FHIR.Python.Setup').PublishDefinition(args.endpoint, assets)

if __name__ == "__main__":
    main()

