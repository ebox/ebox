===============
Getting started
===============

Intro
=====

This tutorial is meant to be an easy-to-follow guide to developing new modules for the eBox platform. You will be able to find further information in our development guide.

We will show you the necessary steps to implement a full-fledged eBox module, using an incremental revision approach.

The eBox development framework has a clear goal: make life easier for those developers who want to provide a UI to manage Unix services integrated with other services on the same machine. We want developers to focus only on adding functionality for the service their modules manage. The framework tries hard to keep you away from messing with HTML, CGIs and so on.

Requirements
============

You should be familiar with a programming language. Although modules are written in Perl, the data structures and syntax should be easily understood by newcomers.

If you want to try out the code, you will need a machine running Ubuntu Hardy or Ubuntu Intrepid. We strongly recommend the use of virtual machines to develop eBox modules.

Installing the necessary stuff
==============================

We will be using emodddev, a collection of convenience scripts that will help us create the directory structure and basic files used by a module.

You will need to add the following repository to your apt sources::

    deb http://ppa.launchpad.net/ebox-unstable/ubuntu hardy main

Install this package by running the following command::

    apt-get install emoddev

On the machine used to test your module you will need to install eBox::

    apt-get install ebox

