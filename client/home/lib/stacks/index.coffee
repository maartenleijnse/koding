kd = require 'kd'
sectionize = require '../commons/sectionize'
headerize = require '../commons/headerize'

HomeStacksCreate = require './homestackscreate'
HomeStacksTeamStacks = require './homestacksteamstacks'
HomeStacksPrivateStacks = require './homestacksprivatestacks'
HomeStacksDrafts = require './homestacksdrafts'
HomeStacksTabHandle = require './homestackstabhandle'

HomeVirtualMachinesVirtualMachines = require '../virtualmachines/homevirtualmachinesvirtualmachines'
HomeVirtualMachinesConnectedMachines = require '../virtualmachines/homevirtualmachinesconnectedmachines'
HomeVirtualMachinesSharedMachines = require '../virtualmachines/homevirtualmachinessharedmachines'

HomeAccountCredentialsView = require '../account/credentials/homeaccountcredentialsview'
EnvironmentFlux = require 'app/flux/environment'

AddManagedMachineModal = require 'app/providers/managed/addmanagedmachinemodal'
VirtualMachinesSelectedMachineFlux = require 'home/virtualmachines/flux/selectedmachine'

module.exports = class HomeStacks extends kd.CustomScrollView

  constructor: (options = {}, data) ->

    options.cssClass = kd.utils.curry 'HomeAppView--scroller', options.cssClass

    super options, data

    @addSubView @topNav  = new kd.TabHandleContainer

    @wrapper.addSubView @tabView = new kd.TabView
      maxHandleWidth       : 'none'
      hideHandleCloseIcons : yes
      detachPanes          : no
      tabHandleContainer   : @topNav
      tabHandleClass       : HomeStacksTabHandle

    @tabView.unsetClass 'kdscrollview'

    @tabView.addPane @stacks      = new kd.TabPaneView { name: 'Stacks' }
    @tabView.addPane @vms         = new kd.TabPaneView { name: 'Virtual Machines' }
    @tabView.addPane @credentials = new kd.TabPaneView { name: 'Credentials' }

    @tabView.showPane @stacks

    # @tabView.on 'PaneDidShow', (pane) ->
    #   { router } = kd.singletons
    #   path = router.getCurrentPath()
    #   router.handleRoute "/Home/Stacks/#{kd.utils.slugify pane.name}"

    { mainController, computeController, reactor } = kd.singletons

    kd.singletons.mainController.ready =>
      @createStacksViews()
      @createVMsViews()
      @createCredentialsViews()


    computeController.on 'MachineBeingDestroyed', (machine) ->
      stack = computeController.findStackFromMachineId machine._id
      reactor.dispatch actions.REMOVE_STACK, stack._id


  handleAction: (action) ->

    for pane in @tabView.panes when kd.utils.slugify(pane.name) is action
      pane_ = @tabView.showPane pane
      if action is 'virtual-machines'
        VirtualMachinesSelectedMachineFlux.actions.setSelectedMachine null
      break

  handleIdentifier: (identifier, action) ->

    for pane in @tabView.panes when kd.utils.slugify(pane.name) is action
      pane_ = @tabView.showPane pane
      if action is 'virtual-machines'
        VirtualMachinesSelectedMachineFlux.actions.setSelectedMachine identifier
      break

  createStacksViews: ->

    EnvironmentFlux.actions.loadTeamStackTemplates()
    EnvironmentFlux.actions.loadPrivateStackTemplates()

    @stacks.addSubView view = new HomeStacksCreate

    view.on 'CreateButtonClick', =>
      @destroy()
      kd.singletons.router.handleRoute '/Stack-Editor/New'

    @stacks.addSubView headerize 'Team Stacks'
    @stacks.addSubView sectionize 'Team Stacks', HomeStacksTeamStacks, { delegate : this }

    @stacks.addSubView headerize 'Private Stacks'
    @stacks.addSubView sectionize 'Private Stacks', HomeStacksPrivateStacks, { delegate : this }

    @stacks.addSubView headerize 'Drafts'
    @stacks.addSubView sectionize 'Drafts', HomeStacksDrafts, { delegate : this }


  createVMsViews: ->

    @vms.addSubView headerize 'Virtual Machines'
    @vms.addSubView sectionize 'Virtual Machines', HomeVirtualMachinesVirtualMachines

    @vms.addSubView header = headerize 'Connected Machines'
    header.addSubView new kd.ButtonView
      cssClass : 'GenericButton HomeAppViewVMSection--addOwnMachineButton'
      title    : 'Add a Connected Machine'
      callback : -> new AddManagedMachineModal

    @vms.addSubView sectionize 'Connected Machines', HomeVirtualMachinesConnectedMachines

    @vms.addSubView headerize 'Shared Machines'
    @vms.addSubView sectionize 'Shared Machines', HomeVirtualMachinesSharedMachines


  createCredentialsViews: ->

    @credentials.addSubView headerize 'Credentials'
    @credentials.addSubView sectionize 'Credentials', HomeAccountCredentialsView