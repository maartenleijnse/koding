_                   = require 'lodash'
kd                  = require 'kd'
React               = require 'kd-react'
ReactDOM            = require 'react-dom'
shortenUrl          = require 'app/util/shortenUrl'
shortenText         = require 'app/util/shortenText'
Portal              = require('react-portal').default
ActivityFlux        = require 'activity/flux'
Link                = require 'app/components/common/link'
SocialShareLinkItem = require './socialsharelinkitem'

module.exports = class ActivitySharePopup extends React.Component

  @defaultProps=
    url      : ''
    onClose  : kd.noop
    isOpened : no
    gplus    : { enabled : yes }
    facebook : { enabled : yes }
    twitter  : { enabled : yes, text : '' }
    linkedin : { enabled : yes, title : 'Koding.com'}


  copyTheClipboard: ->

    shareUrlInput = ReactDOM.findDOMNode @refs.shareUrlInput
    return null  unless shareUrlInput
    event.clipboardData.setData('text/plain', shareUrlInput.value)
    kd.utils.stopDOMEvent event


  componentDidMount: ->

    document.addEventListener 'copy', @bound 'copyTheClipboard'


  componentWillUnmount: ->

    document.removeEventListener 'copy', @bound 'copyTheClipboard'


  componentDidUpdate: ->

    shortenUrl @props.url, (shorten)=>
      shareUrlInput = ReactDOM.findDOMNode @refs.shareUrlInput
      return null  unless shareUrlInput
      shareUrlInput.value = shorten
      shareUrlInput.setSelectionRange(0, shareUrlInput.value.length)


  render: ->

    return null  unless @props.isOpened

    <div className='ActivitySharePopup'>
      <input ref='shareUrlInput' readOnly={yes} type='text' value={@props.url}/>
      <div>
        <Link className='share-icon share-gplus'/>
        <Link className='share-icon share-linkedin'/>
        <Link className='share-icon share-facebook'/>
        <Link className='share-icon share-twitter'/>
      </div>
    </div>

