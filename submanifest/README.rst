Submanifest
***********

``hakanjansson.yaml`` is an example manifest file that can be copied into the submanifests directory. It will add a module ``vscode`` into the directory ``modules/hakanjansson/vscode`` of the Zephyr workspace.

Example use:

.. code-block:: bash

   cd ~/zephyrproject/zephyr/submanifests/
   wget https://raw.githubusercontent.com/hakanjansson/zephyr-vscode/refs/heads/main/submanifest/hakanjansson.yaml
   west update
   west list vscode
