;;; ros.el --- package to interact with and write code for ROS systems

;; Copyright (C) 2019 Max Beutelspacher

;; Author: Max Beutelspacher <max.beutelspacher@mailbox.org>
;; Version: 0.1

;; This file is not part of GNU Emacs.

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; package to interact with and write code for ROS systems

;;; Code:

(defcustom ros-distro (getenv "ROS_DISTRO") "Name of ROS Distribution.")

(defcustom ros-default-workspace (format "/opt/ros/%s"
                                         ros-distro)
  "Path to binary/devel directory of default catkin workspace."
  :group 'ros-workspace
  :type 'directory)

(defvar ros-current-workspace nil "Path to binary/devel directory of current catkin workspace.")

(defun ros-current-workspace ()
  "Return path to binary/devel directory of current catkin workspace or to default workspace if not set."
  (if ros-current-workspace ros-current-workspace
    ros-default-workspace))

(defcustom ros-workspaces '(ros-default-workspace)
  "List of paths to binary/devel directories of catkin workspaces."
  :group 'ros-workspace
  :type 'sexp)

(defvar ros-setup-file-extension (let ((shell (getenv "SHELL")))
                                      (cond
                                       ((s-suffix-p "zsh" shell) ".zsh")
                                       ((s-suffix-p "bash" shell) ".bash")
                                       (t ".sh"))))

(defun ros-source-workspace-command (path)
  "Return the right sourcing command for this workspace at PATH."
  (format "source %s" path))

(defun ros-completing-read-workspace ()
  "Read a workspace from the minibuffer."
  (completing-read "Workspace: " ros-workspaces nil t nil nil (ros-current-workspace)))

(defun ros-select-workspace (path)
  "Set `ros-current-workspace' to PATH."
  (interactive (list (ros-completing-read-workspace)))
  (setq ros-current-workspace path))


(defun ros-shell-command-to-string (cmd)
  "Source the current workspace and run CMD and return the output as string."
  (shell-command-to-string (format "%s && %s" (ros-source-workspace-command (ros-current-workspace)) cmd)))

(defun ros-shell-output-as-list (cmd)
  "Run CMD and return a list of each line of the output."
  (split-string (ros-shell-command-to-string cmd)
                "\n"))

(defun ros-run-process(cmd buffer-name)
  "Source workspace, run CMD, print output in BUFFER-NAME."
  (let ((process (start-process buffer-name buffer-name (format "%s && %s" (ros-source-workspace-command (ros-current-workspace)) cmd))))
    (pop-to-buffer buffer-name)
    (ros-info-mode)))

(defun ros-packages ()
  "List all available ros packages in the current workspace."
  (ros-shell-output-as-list "rospack list-names"))

(defun ros-generic-list (type)
  "Return result from rosTYPE list.

  TYPE can be any of the following \"node\", \"topic\", \"service\" \"msg\""
  (ros-shell-output-as-list (format "ros%s list" type)))

(defun ros-generic-completing-read (type)
  "Prompts for ros TYPE.

  TYPE can be any of the following \"node\", \"topic\", \"service\" \"msg\""
  (completing-read (format "%s: " type) (ros-generic-list type) nil t))

(defun ros-generic-get-info (type name)
  "Return info about NAME of type TYPE.
TYPE can be any of the following \"node\", \"topic\", \"service\" \"msg\""
  (let ((command))
    (setq command (cond ((string= type "msg") "show")
                         (t "info")))
    (ros-shell-command-to-string (format "ros%s %s %s" type command name))))

(defun ros-generic-show-info (type name)
  "Show info about NAME of type TYPE in new buffer."
  (let ((buffer-name (format "* ros-%s: %s" type name)))
    (when (get-buffer buffer-name) (kill-buffer buffer-name))
    (pop-to-buffer buffer-name))
  (erase-buffer)
  (insert (ros-generic-get-info type name))
  (ros-info-mode))

(define-derived-mode ros-info-mode messages-buffer-mode "ros-info-mode"
  "major mode for displaying ros info messages"
  )

(define-key ros-info-mode-map (kbd "S") 'ros-show-thing-at-point)
(define-key ros-info-mode-map (kbd "E") 'ros-echo-topic-at-point)
(define-key ros-info-mode-map (kbd "K") 'ros-kill-node-at-point)

(defun ros-msg-show (msg)
  "Prompt for MSG and show structure."
  (interactive (list (ros-generic-completing-read "msg")))
  (ros-generic-show-info "msg" msg))

(defun ros-topic-show (topic)
  "Prompt for TOPIC and show subscribers and publishers."
  (interactive (list (ros-generic-completing-read "topic")))
  (ros-generic-show-info "topic" topic))
  
(defun ros-service-show (service)
  "Prompt for active SERVICE and show structure."
  (interactive (list (ros-generic-completing-read "service")))
  (ros-generic-show-info "service" service))

(defun ros-srv-show (service)
"Prompt for (not necessarily active) SERVICE and show structure."
(interactive (list (ros-generic-completing-read "srv")))
(ros-generic-show-info "srv" service))

(defun ros-node-show (node)
  "Prompt for NODE and show published and subscribed topics and provided services."
  (interactive (list (ros-generic-completing-read "node")))
  (ros-generic-show-info "node" node))

(defun ros-show-thing-at-point ()
  "Get thing at point and try to describe it."
  (interactive)
  (let ((thing (thing-at-point 'symbol))
        (section (ros-info-get-section))
        (type nil))
    (cond
     ((member section '("Publishers" "Subscribers" "Node"))
      (setq type "node"))
     ((member section '("Subscriptions" "Publications"))
      (setq type "topic"))
     ((member section '("Services"))
      (setq type "service"))
     ((member section '("Type"))
      (cond
       ((member thing (ros-generic-list "msg"))
        (setq type "msg"))
       ((member thing (ros-generic-list "srv"))
        (setq type "srv"))))
     (t (message "Section not recognized")))
    (when type
      (ros-generic-show-info type thing))))

(defun ros-echo-topic-at-point ()
  "Get thing at point and if it is a topic echo it."
  (interactive)
  (let ((thing (thing-at-point 'symbol)))
    (if (member thing (ros-generic-list "topic"))
        (ros-topic-echo thing)
        (message (format "%s is not an active topic" thing)))))


(defun ros-kill-node-at-point ()
  "Get thing at point and if it is a node kill it."
  (interactive)
  (let ((thing (thing-at-point 'symbol)))
    (if (member thing (ros-generic-list "node"))
        (ros-node-kill thing)
      (message (format "%s is not an active node" thing)))))

(defun ros-node-kill (node)
  "Kill NODE if active node."
  (if (member node (ros-generic-list "node"))
      (when (yes-or-no-p (format "Do you really want to kill node %s"
                                 node))
                         (progn
                           (ros-shell-command-to-string (format "rosnode kill %s" node))
                           (if (member node (ros-generic-list "node"))
                               (message (format "Failed to kill node %s" node))
                             (message (format "Killed node %s successfully" node)))))
    (message (format "There is no node %s to kill" node))))

(defun ros-topic-echo (topic)
  "Prompt for TOPIC and echo it."
  (interactive (list (ros-generic-completing-read "topic")))
  (let* ((topic-full-name (if (string-match "^/" topic) topic (concat "/" topic)))
         (buffer-name (concat "*rostopic:" topic-full-name "*"))
         (process (start-process buffer-name buffer-name "rostopic" "echo" topic-full-name)))
    (view-buffer-other-window (process-buffer process))
    (ros-info-mode)))

(defun ros-info-get-section ()
  "Get the section of thing at point."
  (save-excursion
    (let* ((start (re-search-backward "Services:\\|Subscriptions:\\|Publications:\\|Publishers:\\|Subscribers:\\|Node:\\|Type:"))
                 (end (if start (re-search-forward ":"))))
      (when (and start end) (buffer-substring-no-properties start (- end 1))))))

(defun ros-generate-prototype (type name topic)
  (let ((prototype-text (ros-shell-command-to-string (format "rosmsg-proto %s %s" type name)))
        (buffer-name topic))
    (when (get-buffer buffer-name)
      (kill-buffer buffer-name))
    (pop-to-buffer buffer-name)
    (erase-buffer)
    (insert prototype-text)
    (ros-msg-pub-mode)
    ))
  
(define-derived-mode ros-msg-pub-mode text-mode "ros-msg-pub-mode"
  "major mode for publishing ros msg"
  )

(define-key ros-msg-pub-mode-map (kbd "C-c C-c") 'ros-msg-pub-buffer)

(defun ros-msg-pub-buffer (arg)
  (interactive (list current-prefix-arg))
  (let* ((topic (buffer-name))
         (type (ros-get-msg-type topic))
         (message-text (buffer-string))
         (buffer-name (concat "*rostopic pub " topic "*"))
         (old-buffer (current-buffer))
         (rate-argument (if arg (format "-r %d" (prefix-numeric-value arg)) "--once"))
         (process (start-process buffer-name buffer-name "rostopic" "pub" topic type (concat "" message-text) rate-argument)))
    
    (switch-to-buffer (process-buffer process))
    (kill-buffer old-buffer)
    )
  )


(defun ros-get-msg-type (topic)
  (let* ((info (ros-shell-command-to-string (format "rostopic info %s" topic)))
         (test (string-match "Type: \\(.*\\)\n" info)))
    (match-string 1 info)))

(defun ros-msg-pub (topic)
  (interactive (list (ros-generic-completing-read "topic")))
  (ros-generate-prototype "msg" (ros-get-msg-type (s-trim-right topic)) topic))



(provide 'ros)

;;; ros.el ends here
