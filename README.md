<div id="table-of-contents">
<h2>Table of Contents</h2>
<div id="text-table-of-contents">
<ul>
<li><a href="#sec-1">1. Emacs client for the javacomplete auto completion daemon</a></li>
<li><a href="#sec-2">2. Setup</a></li>
</ul>
</div>
</div>

# Emacs client for the javacomplete auto completion daemon<a id="sec-1" name="sec-1"></a>

The completion backend and instructions can be found here:
[github.com/jostillmanns/javacomplete](https://github.com/jostillmanns/javacomplete)

# Setup<a id="sec-2" name="sec-2"></a>

Add the following code to your init.el

    (add-to-list 'load-path "path/to/javacomplete")
    (require 'javacomplete)

The completion is using company-mode. My setup looks like this:

    (defun javainit()
      "tweak some defaults for java and company mode"
      (setq company-tooltip-limit 20)
      (setq company-idle-delay .3)
      (setq company-echo-delay 0)
      (setq company-begin-commands '(self-insert-command))
      (set (make-local-variable 'company-backends) '(company-javacomplete))
      (company-mode))

In order to load with java mode:

    (add-hook 'java-mode-hook 'javainit)