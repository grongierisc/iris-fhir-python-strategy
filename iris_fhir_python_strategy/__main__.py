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
    args = parser.parse_args()

    namespace = args.namespace

    if namespace:
        os.environ['IRISNAMESPACE'] = namespace

    import iris
    iris.cls('%SYSTEM.OBJ').LoadDir(path,'cubk',"*.cls",1)

if __name__ == "__main__":
    main()


