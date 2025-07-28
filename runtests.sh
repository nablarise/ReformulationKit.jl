#!/bin/bash

# Run the Julia command and retry on failure
while true; do
  clear
  julia --project=@. -e "import Pkg; Pkg.test(; test_args = [\"auto\"]);";
  
  # Check exit status
  EXIT_STATUS=$?
  
  if [ $EXIT_STATUS -eq 0 ]; then
    echo "Successful exit of the revise-test loop!"
    break
  elif [ $EXIT_STATUS -eq 222 ]; then
    echo "Tests failed with exit status $EXIT_STATUS. Retrying in 3 seconds..."
    sleep 3
  else
    echo "Tests failed with exit status $EXIT_STATUS."
    echo "This case is not handled. Fix the error and try again."
    break
  fi
done